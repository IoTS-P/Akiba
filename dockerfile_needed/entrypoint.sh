#!/bin/bash
set -e

INIT_FLAG="/home/akiba/.init"
DAEMON_DIR="/home/akiba/akiba_db_daemon"
FRAMEWORK_DIR="/home/akiba/akiba_framework"
CONFIG="${DAEMON_DIR}/resources/config.json"
PID_FILE="/tmp/akiba_db_daemon.pid"

# Wait for db daemon ready
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

# Stop service safely
cleanup() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo ">>> Stopping akiba_db_daemon... (PID: $pid)"
            kill "$pid" || true
            wait "$pid" 2>/dev/null || true
        fi
        rm -f "$PID_FILE"
    fi
}

# Make sure to cleanup
trap cleanup EXIT

# ========== Initialization ==========
if [ ! -f "$INIT_FLAG" ]; then
    echo ">>> Startup for the first time, initializing..."

    # 1. Start the service in background (Use & and record pid)
    echo ">>> Running temporary akiba_db_daemon..."
    cd "$DAEMON_DIR"
    sudo service postgresql start
    ./resources/initialize_pg_local.sh  # Initialize 5432 PostgreSQL server
    nohup ./bin/akiba_db_daemon -c "$CONFIG" > /dev/null 2>&1 &
    DAEMON_PID=$!
    echo $DAEMON_PID > "$PID_FILE"

    # 2. Wait for HTTP ready
    if ! wait_for_service "http://localhost:31777/test"; then
        echo ">>> Service failed to start: "
        cat /home/akiba/.akiba/daemon.log || true
        exit 1
    fi

    # 3. Execute initialization for one shot
    echo ">>> Creating PostgreSQL instance for akiba..."
    cd "$FRAMEWORK_DIR"
    if ! ./bin/akiba_framework instance-create \
        -i akiba-instance \
        -u akiba \
        -P akiba; then
        echo ">>> Initialization failed"
        exit 1
    fi

    # 4. Clean up temporary service
    cleanup

    # 5. Create flag file
    touch "$INIT_FLAG"
    echo ">>> Initialization finished with flag file: $INIT_FLAG"
else
    echo ">>> Initialization already done"
fi

# ========== Run main service and block ==========
echo ">>> Starting main service (akiba database daemon): " "$@"
cd "$DAEMON_DIR"

# Use exec to substitute current process
exec "$@"