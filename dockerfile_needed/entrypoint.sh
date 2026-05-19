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
AKIBA_DB_PASSWORD="akiba123"

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

# Create users database for akiba_server if not exists
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = 'akiba_users'" | grep -q 1 || \
    sudo -u postgres createdb -E UTF8 akiba_users || true

# Create akiba user if not exists with password
if ! sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname = 'akiba'" | grep -q 1; then
    sudo -u postgres createuser -d akiba || true
fi

# Set password for akiba user
sudo -u postgres psql -c "ALTER USER akiba WITH PASSWORD '${AKIBA_DB_PASSWORD}';" || true

# Grant all privileges on akiba_users database to akiba user
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE akiba_users TO akiba;" || true
sudo -u postgres psql -d akiba_users -c "GRANT ALL PRIVILEGES ON SCHEMA public TO akiba;" || true
sudo -u postgres psql -d akiba_users -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO akiba;" || true
sudo -u postgres psql -d akiba_users -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO akiba;" || true

# Configure PostgreSQL to allow password authentication for local connections
sudo sed -i 's/local   all             all                                     peer/local   all             all                                     md5/' /etc/postgresql/16/main/pg_hba.conf || true
sudo sed -i 's/host    all             all             127.0.0.1\/32            scram-sha-256/host    all             all             127.0.0.1\/32            md5/' /etc/postgresql/16/main/pg_hba.conf || true
sudo sed -i 's/host    all             all             ::1\/128                 scram-sha-256/host    all             all             ::1\/128                 md5/' /etc/postgresql/16/main/pg_hba.conf || true

# Reload PostgreSQL config
sudo service postgresql reload || true

# ========== Initialize akiba_server database and default user ==========
if ! sudo -u postgres psql -d akiba_users -c "SELECT 1 FROM users LIMIT 1" > /dev/null 2>&1; then
    echo ">>> Setting up akiba_server database schema and default user..."

    # Create tables using akiba_server's built-in schema creation
    # Then create default user using Python bcrypt
    sudo -u postgres psql -d akiba_users <<'EOF'
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    token VARCHAR(512) UNIQUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS scripts (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    code TEXT NOT NULL,
    output TEXT,
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT now(),
    finished_at TIMESTAMPTZ
);
EOF
else
    echo ">>> akiba_server database already initialized"
fi

# ========== First Time Initialization ==========
if [ ! -f "$INIT_FLAG" ]; then
    echo ">>> First time startup, initializing..."

    # 1. Start temporary db daemon
    echo ">>> Running temporary akiba_db_daemon..."
    cd "$DAEMON_DIR"
    nohup ./bin/akiba_db_daemon -c "$CONFIG" > /dev/null 2>&1 &
    DAEMON_PID=$!
    echo $DAEMON_PID > "$DB_DAEMON_PID"

    # 2. Wait for db daemon HTTP ready
    if ! wait_for_service "http://localhost:${DB_DAEMON_PORT}/test"; then
        echo ">>> Database daemon failed to start"
        cat /home/akiba/.akiba/daemon.log || true
        exit 1
    fi

    # 3. Create default instance
    echo ">>> Creating PostgreSQL instance for akiba..."
    cd "$FRAMEWORK_DIR"
    if ! ./bin/akiba instance-create \
        -i akiba-instance \
        -u akiba \
        -P akiba; then
        echo ">>> Instance creation failed"
        exit 1
    fi

    # 4. Stop temporary db daemon (but NOT PostgreSQL)
    cleanup

    # 5. Create flag file
    touch "$INIT_FLAG"
    echo ">>> Initialization finished"
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

# Create default user if not exists
if ! sudo -u postgres psql -d akiba_users -c "SELECT 1 FROM users WHERE username='akiba'" | grep -q 1; then
    echo ">>> Creating default user 'akiba'..."
    REGISTER_RESP=$(curl -s -X POST "http://localhost:${SERVER_PORT}/api/auth/register" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"akiba\",\"password\":\"akiba123\"}" || echo "")
    if echo "$REGISTER_RESP" | grep -q "token"; then
        echo ">>> Default user 'akiba' created successfully"
    else
        echo ">>> Warning: Failed to create default user"
    fi
else
    echo ">>> Default user 'akiba' already exists"
fi

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

# Block and wait for signals
wait
