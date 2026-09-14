#!/bin/bash
set -e

INIT_FLAG="/home/akiba/.init"
DAEMON_DIR="/home/akiba/akiba_db_daemon"
FRAMEWORK_DIR="/home/akiba/akiba_framework"
CONFIG="${DAEMON_DIR}/resources/config.json"
DB_DAEMON_PID="/tmp/akiba_db_daemon.pid"
SERVER_PID="/tmp/akiba_server.pid"
SERVER_PORT=8080
DB_DAEMON_PORT=31777
AKIBA_DB_PORT=5432

# ---------------------------------------------------------------------------
# Database password
# ---------------------------------------------------------------------------
# No fixed password is shipped any more. The PostgreSQL password of the `akiba`
# role is generated on first boot and kept in a file that only the akiba user
# can read, so restarts reuse it. It is exported because the database daemon
# (which owns the backup bookkeeping databases) and the Akiba server both need
# it — the daemon refuses to run without a password rather than falling back to
# a well-known default.
PASSWORD_FILE="/home/akiba/.akiba/db_password"
mkdir -p "$(dirname "$PASSWORD_FILE")"
if [ -s "$PASSWORD_FILE" ]; then
    AKIBA_DB_PASSWORD="$(cat "$PASSWORD_FILE")"
else
    AKIBA_DB_PASSWORD="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)"
    (umask 077; printf '%s' "$AKIBA_DB_PASSWORD" > "$PASSWORD_FILE")
    chmod 600 "$PASSWORD_FILE"
    echo ">>> Generated a new database password (stored in ${PASSWORD_FILE})"
fi
export AKIBA_DB_PASSWORD

wait_for_service() {
    local url=$1
    local max_attempts=30
    local attempt=1

    echo ">>> Waiting for service ready: ${url}"
    while [ $attempt -le $max_attempts ]; do
        if curl -s --max-time 2 "${url}" > /dev/null 2>&1; then
            echo ">>> Service ready (${attempt}s)"
            return 0
        fi
        echo "    Waiting... (${attempt}/${max_attempts})"
        sleep 1
        attempt=$((attempt + 1))
    done

    echo ">>> Error: service not ready until timeout"
    return 1
}

cleanup() {
    echo ">>> Cleaning up..."

    echo ">>> Stopping nginx..."
    sudo nginx -s stop 2>/dev/null || true

    if [ -f "$SERVER_PID" ]; then
        local server_pid=$(cat "$SERVER_PID")
        if kill -0 "$server_pid" 2>/dev/null; then
            echo ">>> Stopping akiba_server... (PID: $server_pid)"
            kill "$server_pid" || true
            wait "$server_pid" 2>/dev/null || true
        fi
        rm -f "$SERVER_PID"
    fi

    if [ -f "$DB_DAEMON_PID" ]; then
        local daemon_pid=$(cat "$DB_DAEMON_PID")
        if kill -0 "$daemon_pid" 2>/dev/null; then
            echo ">>> Stopping akiba_db_daemon... (PID: $daemon_pid)"
            kill "$daemon_pid" || true
            wait "$daemon_pid" 2>/dev/null || true
        fi
        rm -f "$DB_DAEMON_PID"
    fi
}

# Trap EXIT but only for the main process (not subprocesses)
trap cleanup EXIT

# ========== PostgreSQL Setup ==========
echo ">>> Starting PostgreSQL..."
sudo service postgresql start

# Wait for PostgreSQL to be ready
max_pg_wait=30
attempt=1
while [ $attempt -le $max_pg_wait ]; do
    if sudo -u postgres psql -c "SELECT 1" > /dev/null 2>&1; then
        echo ">>> PostgreSQL ready (${attempt}s)"
        break
    fi
    echo "    Waiting for PostgreSQL... (${attempt}/${max_pg_wait})"
    sleep 1
    attempt=$((attempt + 1))
done

if [ $attempt -gt $max_pg_wait ]; then
    echo ">>> Error: PostgreSQL failed to start"
    exit 1
fi

# Create the akiba role if missing. It owns every Akiba database, so it needs the
# createdb right; the databases themselves are provisioned by prepare_database()
# further down, always with akiba as their owner.
if ! sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname = 'akiba'" | grep -q 1; then
    sudo -u postgres createuser -d akiba || true
fi

# Set password for akiba user
sudo -u postgres psql -c "ALTER USER akiba WITH PASSWORD '${AKIBA_DB_PASSWORD}';" || true

# Configure PostgreSQL to allow password authentication for local connections
sudo sed -i 's/local   all             all                                     peer/local   all             all                                     md5/' /etc/postgresql/16/main/pg_hba.conf || true
sudo sed -i 's/host    all             all             127.0.0.1\/32            scram-sha-256/host    all             all             127.0.0.1\/32            md5/' /etc/postgresql/16/main/pg_hba.conf || true
sudo sed -i 's/host    all             all             ::1\/128                 scram-sha-256/host    all             all             ::1\/128                 md5/' /etc/postgresql/16/main/pg_hba.conf || true

# Reload PostgreSQL config
sudo service postgresql reload || true

# ========== Provision the databases the akiba role owns ==========
# Every Akiba database is created *owned by* akiba, so the tables the applications
# create inside it are owned by akiba as well and start-up needs no ownership
# fix-up. The table definitions live with the code that uses them, and are not
# repeated here:
#
#   akiba_users  → ServerDatabase.initSchema()                     (users, user_sessions)
#   akiba_backup → resources/backup_db_init.sql                    (db_backup_tree)
#   per-instance → resources/database_init.sql, agent_database_init.sql
#                  (applied by the daemon when it creates a user's instance; that
#                   is where `scripts` lives — it is not part of akiba_users)
#
# "ALTER TABLE ... OWNER TO" statements used to live here for databases created by
# images up to 4.3.0, whose entrypoint ran the server DDL itself as the postgres
# superuser. Owning the database removes the cause instead of patching it: the
# only remnant is the one-off bulk hand-over at the end of this function.
prepare_database() {
    local db="$1"

    if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${db}'" | grep -q 1; then
        sudo -u postgres psql -c "CREATE DATABASE ${db} OWNER akiba;" > /dev/null 2>&1 \
            && echo ">>> Database '${db}' created (owner akiba)"
    else
        local owner
        owner=$(sudo -u postgres psql -tAc \
            "SELECT pg_catalog.pg_get_userbyid(datdba) FROM pg_database WHERE datname='${db}';")
        if [[ "$owner" != "akiba" ]]; then
            echo ">>> Database '${db}' exists with owner '${owner}'; transferring to akiba"
            sudo -u postgres psql -c "ALTER DATABASE ${db} OWNER TO akiba;" > /dev/null 2>&1
        fi
    fi

    # PostgreSQL 15+ ties the public schema to pg_database_owner, so owning the
    # database is already enough to create tables in it; the rest keeps databases
    # created by older PostgreSQL setups working.
    sudo -u postgres psql -d "${db}" > /dev/null 2>&1 <<'SQL' || true
ALTER SCHEMA public OWNER TO akiba;
GRANT USAGE, CREATE ON SCHEMA public TO akiba;
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO akiba;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO akiba;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES    TO akiba;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO akiba;
SQL

    # Objects created by images up to 4.3.0 belong to the postgres superuser, and a
    # table owned by postgres makes a later migration such as "add users.is_admin"
    # fail with `ERROR: must be owner of table users`. They are handed over here, so
    # upgrading needs no manual step; a fresh database is owned by akiba, so there is
    # usually nothing to do.
    #
    # The names come from the catalog instead of a hardcoded list (the previous list
    # had already drifted: `scripts` does not live in this database), and the hand-over
    # has to be one `ALTER TABLE/SEQUENCE ... OWNER TO` per object, because
    # `REASSIGN OWNED BY postgres` is refused with "cannot reassign ownership of
    # objects owned by role postgres because they are required by the database system".
    local foreign
    foreign=$(sudo -u postgres psql -d "${db}" -tAc \
        "SELECT count(*) FROM pg_class c
           JOIN pg_roles r ON r.oid = c.relowner
          WHERE r.rolname = 'postgres'
            AND c.relkind IN ('r','S')
            AND c.relnamespace = 'public'::regnamespace;")
    if [[ "${foreign:-0}" != "0" ]]; then
        echo ">>> Database '${db}': ${foreign} table(s)/sequence(s) from an older image are owned by 'postgres'; transferring to akiba"
        sudo -u postgres psql -d "${db}" -v ON_ERROR_STOP=1 <<'SQL' \
            || echo ">>> WARNING: ownership transfer failed (see above). The server prints the exact statement it needs if a migration hits such a table."
DO $$
DECLARE obj record;
BEGIN
    FOR obj IN
        SELECT c.relname, c.relkind
          FROM pg_class c
          JOIN pg_roles r ON r.oid = c.relowner
         WHERE r.rolname = 'postgres'
           AND c.relkind IN ('r','S')
           AND c.relnamespace = 'public'::regnamespace
    LOOP
        IF obj.relkind = 'S' THEN
            EXECUTE format('ALTER SEQUENCE public.%I OWNER TO akiba', obj.relname);
        ELSE
            EXECUTE format('ALTER TABLE public.%I OWNER TO akiba', obj.relname);
        END IF;
        RAISE NOTICE 'owner of % set to akiba', obj.relname;
    END LOOP;
END
$$;
SQL
    fi
}

echo ">>> Preparing the databases owned by 'akiba'..."
prepare_database akiba_users

# ========== Backup database akiba_backup (same owner rules) ==========

DB_NAME=akiba_backup
prepare_database "${DB_NAME}"

DB_INIT_SQL="./resources/backup_db_init.sql"

if [[ ! -f "$DB_INIT_SQL" ]]; then
    echo "SQL file not found: $DB_INIT_SQL"
    exit 1
fi

echo "Executing SQL file '$DB_INIT_SQL' on database '$DB_NAME'..."

# Run the file *as akiba* (SET ROLE) so the objects it creates are owned by akiba
# straight away, like everything else in a database this script provisions. Applied
# as postgres they would be owned by the superuser, and the daemon — which connects
# as akiba — would only keep working thanks to the blanket GRANTs below, while any
# later ALTER on those tables would need the same ownership repair the server tables
# needed.
sudo -u postgres psql \
    --dbname="$DB_NAME" \
    --set=ON_ERROR_STOP=on \
    --command="SET ROLE akiba;" \
    --file="$DB_INIT_SQL"

echo "SQL initialization completed successfully."

# ========== First Time Initialization ==========
# Nothing is created here on purpose. Earlier versions of this script created a
# default instance (`akiba-instance`) at first boot, which then belonged to
# whichever default account the script also created. Instances are now created
# by the user who wants one, on their first visit to the web UI, and no account
# is shipped at all (the first visit offers a setup form for the administrator).
#
# The flag file is still written so that a container restarted from an older
# image does not re-run the (now removed) initialization once.
if [ ! -f "$INIT_FLAG" ]; then
    echo ">>> First time startup: no default account or instance is created."
    touch "$INIT_FLAG"
    echo ">>> Initialization finished"
fi

# ========== Apply staged updates (if any) ==========
# The auto_update.sh --daemon process downloads new artifacts to a
# staging directory.  We apply them HERE — before services start — so
# the new code is live the moment the container comes up.  This is the
# only safe window: JARs are not yet loaded by any process.
if [ -f /home/akiba/binaries/auto_update.sh ]; then
    /home/akiba/binaries/auto_update.sh --apply || true
fi

# ========== Start Main Services ==========

# Start db daemon
echo ">>> Starting akiba_db_daemon..."
cd "$DAEMON_DIR"
nohup ./bin/akiba_db_daemon -c "$CONFIG" > /dev/null 2>&1 &
echo $! > "$DB_DAEMON_PID"

if ! wait_for_service "http://localhost:${DB_DAEMON_PORT}/test"; then
    echo ">>> Database daemon failed to start"
    exit 1
fi

echo ">>> Starting akiba_server..."
cd "$FRAMEWORK_DIR"
nohup ./bin/akiba server \
    --host 0.0.0.0 \
    --port $SERVER_PORT \
    --db-host localhost \
    --db-port 5432 \
    --db-name akiba_users \
    --db-user akiba \
    --db-password "${AKIBA_DB_PASSWORD}" \
    --daemon-host localhost \
    --daemon-port $DB_DAEMON_PORT \
    > /tmp/akiba_server.log 2>&1 &
echo $! > "$SERVER_PID"

echo ">>> Waiting for akiba_server..."
if ! wait_for_service "http://localhost:${SERVER_PORT}/api/health"; then
    echo ">>> Akiba server failed to start"
    cat /tmp/akiba_server.log || true
    exit 1
fi

# No default account is created. Open the web UI once and complete the setup
# form: it creates the first (administrator) account, and the first user then
# creates their own database instance.

echo ">>> Starting nginx for frontend..."
sudo nginx

echo ""
echo "=============================================="
echo "Services started successfully:"
echo "  - akiba_db_daemon: http://localhost:${DB_DAEMON_PORT}"
echo "  - akiba_server:    http://localhost:${SERVER_PORT}"
echo "  - akiba_frontend:  http://localhost:80"
echo "=============================================="
echo ""

# ========== Start background update checker ==========
# Checks GitHub for new releases every 3 days and downloads them to
# the staging directory.  Updates are applied on the NEXT restart
# (by the --apply block above).  The frontend can also trigger a
# manual check via the /api/update/check endpoint.
if [ -f /home/akiba/binaries/auto_update.sh ]; then
    nohup /home/akiba/binaries/auto_update.sh --daemon > /tmp/auto_update.log 2>&1 &
    echo ">>> Auto-update checker started (checks every 3 days)"
fi

# Block and wait for signals
wait
