#!/usr/bin/env bash

set -euo pipefail

REQUIRED_VERSION=12

echo "== Akiba initialization started =="

# -----------------------------
# 1. Check if PostgreSQL exists
# -----------------------------
if ! command -v psql >/dev/null 2>&1; then
    echo "PostgreSQL is not installed. Please install it via apt first."
    exit 1
fi

# -----------------------------
# 2. Check if PostgreSQL version is supported
# -----------------------------
PG_VERSION_RAW=$(psql --version | awk '{print $3}')
PG_MAJOR_VERSION=${PG_VERSION_RAW%%.*}

if [[ "$PG_MAJOR_VERSION" -lt "$REQUIRED_VERSION" ]]; then
    echo "PostgreSQL version $PG_VERSION_RAW detected."
    echo "Version must be >= $REQUIRED_VERSION."
    exit 1
fi

echo "PostgreSQL version $PG_VERSION_RAW OK."

# -----------------------------
# 3. Configure PostgreSQL authentication
# -----------------------------
PG_CONF_DIR="/etc/postgresql/${PG_MAJOR_VERSION}/main"
sudo sed -i 's/local   all             all                                     peer/local   all             all                                     md5/' "${PG_CONF_DIR}/pg_hba.conf" || true
sudo sed -i 's/host    all             all             127.0.0.1\/32            scram-sha-256/host    all             all             127.0.0.1\/32            md5/' "${PG_CONF_DIR}/pg_hba.conf" || true
sudo sed -i 's/host    all             all             ::1\/128                 scram-sha-256/host    all             all             ::1\/128                 md5/' "${PG_CONF_DIR}/pg_hba.conf" || true

# Reload PostgreSQL config
sudo service postgresql reload || true

# -----------------------------
# 4. Setup akiba user and akiba_users database (for akiba_server)
# -----------------------------
USER=akiba
USER_EXISTS=$(sudo -u postgres psql -tAc \
    "SELECT 1 FROM pg_roles WHERE rolname='${USER}';" 2>/dev/null || echo "")

if [[ "$USER_EXISTS" != "1" ]]; then
    echo "Creating role '${USER}'..."
    sudo -u postgres createuser -d "${USER}" 2>/dev/null || true
    sudo -u postgres psql -c "ALTER USER ${USER} WITH PASSWORD 'akiba';" 2>/dev/null || true
    echo "User '${USER}' created."
else
    echo "User '${USER}' already exists."
fi

# Create akiba_users database for akiba_server
DB_NAME_USERS=akiba_users
DB_EXISTS=$(sudo -u postgres psql -tAc \
    "SELECT 1 FROM pg_database WHERE datname='${DB_NAME_USERS}';" 2>/dev/null || echo "")

if [[ "$DB_EXISTS" != "1" ]]; then
    echo "Creating database '${DB_NAME_USERS}'..."
    sudo -u postgres createdb -E UTF8 "${DB_NAME_USERS}" 2>/dev/null || true
    echo "Database '${DB_NAME_USERS}' created."
else
    echo "Database '${DB_NAME_USERS}' already exists."
fi

# Grant privileges
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME_USERS} TO ${USER};" 2>/dev/null || true
sudo -u postgres psql -d "${DB_NAME_USERS}" -c "GRANT ALL PRIVILEGES ON SCHEMA public TO ${USER};" 2>/dev/null || true
sudo -u postgres psql -d "${DB_NAME_USERS}" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO ${USER};" 2>/dev/null || true
sudo -u postgres psql -d "${DB_NAME_USERS}" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO ${USER};" 2>/dev/null || true

# -----------------------------
# 5. Create akiba_server tables in akiba_users database
# -----------------------------
echo "Creating akiba_server tables in '${DB_NAME_USERS}'..."

sudo -u postgres psql -d "${DB_NAME_USERS}" <<'EOF'
-- Users table for authentication
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- User sessions for JWT token management
CREATE TABLE IF NOT EXISTS user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    token VARCHAR(512) UNIQUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);

-- Scripts execution history
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

echo "akiba_server tables created."

# -----------------------------
# 6. Create default user akiba/akiba
# -----------------------------
echo "Creating default user 'akiba'..."

sudo -u postgres psql -d "${DB_NAME_USERS}" <<'EOF'
-- Check if user exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM users WHERE username = 'akiba') THEN
        -- Create user with bcrypt hash of 'akiba'
        -- bcrypt('akiba') = $2a$10$... (10 rounds)
        INSERT INTO users (username, password_hash)
        VALUES ('akiba', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZRGdjGj/n3.rsS2/7JU3ALzF7W4G2');
        RAISE NOTICE 'Default user akiba created';
    ELSE
        RAISE NOTICE 'Default user akiba already exists';
    END IF;
END $$;
EOF

# -----------------------------
# 7. Create akiba-instance for akiba_db_daemon
# -----------------------------
DAEMON_DIR="${HOME}/akiba_db_daemon"
CONFIG="${DAEMON_DIR}/resources/config.json"
INSTANCE_ROOT="${HOME}/instances"

if [[ -f "$CONFIG" ]] && [[ -d "$DAEMON_DIR" ]]; then
    echo "Initializing akiba-instance for akiba_db_daemon..."

    # Start temporary db daemon
    cd "$DAEMON_DIR"
    nohup ./bin/akiba_db_daemon -c "$CONFIG" > /dev/null 2>&1 &
    DAEMON_PID=$!
    echo "Started akiba_db_daemon (PID: $DAEMON_PID)"

    # Wait for daemon to be ready
    max_wait=30
    attempt=1
    while [ $attempt -le $max_wait ]; do
        if curl -s --max-time 2 "http://localhost:31777/test" > /dev/null 2>&1; then
            echo "akiba_db_daemon ready (${attempt}s)"
            break
        fi
        echo "    Waiting for daemon... (${attempt}/${max_wait})"
        sleep 1
        attempt=$((attempt + 1))
    done

    if [ $attempt -gt $max_wait ]; then
        echo "Warning: akiba_db_daemon failed to start, skipping instance creation"
        kill $DAEMON_PID 2>/dev/null || true
    else
        # Create instance
        FRAMEWORK_DIR="${HOME}/akiba_framework"
        if [[ -d "$FRAMEWORK_DIR" ]] && [[ -x "$FRAMEWORK_DIR/bin/akiba" ]]; then
            echo "Creating akiba-instance..."
            cd "$FRAMEWORK_DIR"
            if ./bin/akiba instance-create -i akiba-instance -u akiba -P akiba 2>/dev/null; then
                echo "akiba-instance created successfully"
            else
                echo "Warning: akiba-instance creation failed (may already exist)"
            fi
        else
            echo "Warning: akiba_framework not found, skipping instance creation"
        fi

        # Stop temporary daemon
        echo "Stopping temporary akiba_db_daemon..."
        kill $DAEMON_PID 2>/dev/null || true
        wait $DAEMON_PID 2>/dev/null || true
    fi
else
    echo "Warning: akiba_db_daemon not found, skipping instance creation"
fi

echo "== Akiba initialization completed =="