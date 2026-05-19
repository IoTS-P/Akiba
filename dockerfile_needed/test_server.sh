#!/usr/bin/env bash

set -e

SERVER_HOST="${SERVER_HOST:-localhost}"
SERVER_PORT="${SERVER_PORT:-8080}"
DAEMON_HOST="${DAEMON_HOST:-localhost}"
DAEMON_PORT="${DAEMON_PORT:-31777}"
AKIBA_FRAMEWORK_DIR="/home/akiba/akiba_framework"
AKIBA_BIN="${AKIBA_FRAMEWORK_DIR}/bin/akiba"
BINARIES_DIR="/home/akiba/binaries"
AKIBA_USER="akiba"
AKIBA_PASS="akiba"
AKIBA_DB_NAME="akiba-instance"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
fail() { log_error "$1"; exit 1; }

wait_for_service() {
    local url=$1
    local max_attempts=30
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if curl -s --max-time 2 "$url" > /dev/null 2>&1; then
            return 0
        fi
        echo -n "."
        sleep 1
        attempt=$((attempt + 1))
    done
    return 1
}

echo ""
echo "********************************************************************************"
echo "**************** Akiba All-in-One Test Suite ***********************************"
echo "********************************************************************************"
echo ""

echo "********************************************************************************"
echo "**************** Part 1: Akiba Command Line Tests ******************************"
echo "********************************************************************************"
echo ""

echo ">>> Step 1.1: Check database daemon..."
if ! curl -sf http://${DAEMON_HOST}:${DAEMON_PORT}/test > /dev/null; then
    fail "Database daemon is not running or not accessible!"
fi
log_info "Database daemon is running normally."
echo ""

echo ">>> Step 1.2: Check PostgreSQL instance is running..."
PG_PORT=31800
if ! sudo -u postgres psql -p ${PG_PORT} -c "SELECT 1;" > /dev/null 2>&1; then
    log_warn "PostgreSQL instance not accessible on port ${PG_PORT}, checking if it's starting..."
    if sudo -u postgres pg_ctl -D /akiba/instances/akiba-instance status > /dev/null 2>&1; then
        log_info "PostgreSQL instance is starting up"
    fi
else
    log_info "PostgreSQL instance is running normally."
fi
echo ""

echo ">>> Step 1.3: Run import and process test tasks..."
cd "${AKIBA_FRAMEWORK_DIR}" || exit 1

mkdir -p modules
cp "${BINARIES_DIR}"/amod*.jar modules 2>/dev/null || log_warn "No module jars found, skipping..."

if [ -f "${BINARIES_DIR}/config_example.json" ] && [ -f "${BINARIES_DIR}/import_example.json" ]; then
    log_info "Running import task..."
    "${AKIBA_BIN}" -c "${BINARIES_DIR}/config_example.json" -i "${BINARIES_DIR}/import_example.json" || log_warn "Import task failed or incomplete"
fi

if [ -f "${BINARIES_DIR}/config_run_example.json" ]; then
    log_info "Running process task..."
    "${AKIBA_BIN}" -c "${BINARIES_DIR}/config_run_example.json@/process_1" || log_warn "Process task failed or incomplete"
fi
echo ""

echo ">>> Step 1.4: Verify database data..."
DATA_EXISTS=$(sudo -u postgres psql -p ${PG_PORT} --dbname=${AKIBA_DB_NAME} -t -c "SELECT COUNT(*) FROM binaries;" 2>/dev/null | tr -d ' ' || echo "0")
if [ "${DATA_EXISTS}" -gt 0 ]; then
    log_info "Database has ${DATA_EXISTS} binary records."
else
    log_warn "Database binaries table is empty or inaccessible."
fi
echo ""

echo ">>> Step 1.5: Test instance management commands..."
log_info "Testing instance-list..."
"${AKIBA_BIN}" instance-list || log_warn "instance-list failed"

log_info "Testing instance-status..."
"${AKIBA_BIN}" instance-status -i akiba-instance || log_warn "instance-status failed"
echo ""

echo "********************************************************************************"
echo "**************** Part 2: Akiba Server API Tests ******************************"
echo "********************************************************************************"
echo ""

echo ">>> Step 2.1: Wait for server to be ready..."
printf "Waiting for server"
if ! wait_for_service "http://${SERVER_HOST}:${SERVER_PORT}/api/health"; then
    fail "Akiba server is not running!"
fi
echo ""
log_info "Server is ready."
echo ""

echo ">>> Step 2.2: Test public endpoints (no auth required)..."

echo "  - GET /"
ROOT_RESPONSE=$(curl -sf http://${SERVER_HOST}:${SERVER_PORT}/)
if [ "$ROOT_RESPONSE" = "Akiba Server is running" ]; then
    log_info "  GET / - OK: ${ROOT_RESPONSE}"
else
    log_warn "  GET / - Unexpected: ${ROOT_RESPONSE}"
fi

echo "  - GET /api/health"
HEALTH_RESPONSE=$(curl -sf http://${SERVER_HOST}:${SERVER_PORT}/api/health)
if echo "$HEALTH_RESPONSE" | grep -q '"status"'; then
    log_info "  GET /api/health - OK: ${HEALTH_RESPONSE}"
else
    log_error "  GET /api/health - Failed: ${HEALTH_RESPONSE}"
fi
echo ""

echo ">>> Step 2.3: Test authentication endpoints..."

echo "  - POST /api/auth/register (new user)"
REGISTER_RESPONSE=$(curl -sf -X POST http://${SERVER_HOST}:${SERVER_PORT}/api/auth/register \
    -H "Content-Type: application/json" \
    -d '{"username":"testuser1","password":"testpass123"}')
if echo "$REGISTER_RESPONSE" | grep -q '"token"'; then
    TEST_TOKEN=$(echo "$REGISTER_RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    TEST_USER_ID=$(echo "$REGISTER_RESPONSE" | grep -o '"userId":[0-9]*' | cut -d':' -f2)
    log_info "  POST /api/auth/register - OK: userId=${TEST_USER_ID}"
else
    log_warn "  POST /api/auth/register - Failed or user exists: ${REGISTER_RESPONSE}"
    echo "  - POST /api/auth/login (existing user)"
    REGISTER_RESPONSE=$(curl -sf -X POST http://${SERVER_HOST}:${SERVER_PORT}/api/auth/login \
        -H "Content-Type: application/json" \
        -d '{"username":"testuser1","password":"testpass123"}')
    if echo "$REGISTER_RESPONSE" | grep -q '"token"'; then
        TEST_TOKEN=$(echo "$REGISTER_RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
        TEST_USER_ID=$(echo "$REGISTER_RESPONSE" | grep -o '"userId":[0-9]*' | cut -d':' -f2)
        log_info "  POST /api/auth/login - OK: userId=${TEST_USER_ID}"
    else
        log_error "  POST /api/auth/login - Failed: ${REGISTER_RESPONSE}"
    fi
fi

echo ""
echo "  - POST /api/auth/login (valid credentials)"
LOGIN_RESPONSE=$(curl -sf -X POST http://${SERVER_HOST}:${SERVER_PORT}/api/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"testuser1","password":"testpass123"}')
if echo "$LOGIN_RESPONSE" | grep -q '"token"'; then
    TEST_TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    TEST_USER_ID=$(echo "$LOGIN_RESPONSE" | grep -o '"userId":[0-9]*' | cut -d':' -f2)
    log_info "  POST /api/auth/login - OK: userId=${TEST_USER_ID}"
else
    log_error "  POST /api/auth/login - Failed: ${LOGIN_RESPONSE}"
fi

echo ""
echo "  - POST /api/auth/login (invalid credentials)"
INVALID_LOGIN=$(curl -sf -X POST http://${SERVER_HOST}:${SERVER_PORT}/api/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"testuser1","password":"wrongpassword"}')
if echo "$INVALID_LOGIN" | grep -q '"message"'; then
    log_info "  POST /api/auth/login (invalid) - OK: rejected as expected"
else
    log_warn "  POST /api/auth/login (invalid) - Unexpected response: ${INVALID_LOGIN}"
fi

echo ""
echo "  - POST /api/auth/register (duplicate username)"
DUPE_REGISTER=$(curl -sf -X POST http://${SERVER_HOST}:${SERVER_PORT}/api/auth/register \
    -H "Content-Type: application/json" \
    -d '{"username":"testuser1","password":"anotherpass"}')
if echo "$DUPE_REGISTER" | grep -q '"message"' || echo "$DUPE_REGISTER" | grep -q '"error"'; then
    log_info "  POST /api/auth/register (duplicate) - OK: rejected as expected"
else
    log_warn "  POST /api/auth/register (duplicate) - Unexpected: ${DUPE_REGISTER}"
fi

echo ""
echo "  - GET /api/auth/me (with valid token)"
ME_RESPONSE=$(curl -sf -H "Authorization: Bearer ${TEST_TOKEN}" http://${SERVER_HOST}:${SERVER_PORT}/api/auth/me)
if echo "$ME_RESPONSE" | grep -q '"username"'; then
    log_info "  GET /api/auth/me - OK: ${ME_RESPONSE}"
else
    log_error "  GET /api/auth/me - Failed: ${ME_RESPONSE}"
fi

echo ""
echo "  - GET /api/auth/me (without token)"
ME_NO_TOKEN=$(curl -sf http://${SERVER_HOST}:${SERVER_PORT}/api/auth/me)
if echo "$ME_NO_TOKEN" | grep -q '"message"' || echo "$ME_NO_TOKEN" | grep -q '"error"'; then
    log_info "  GET /api/auth/me (no token) - OK: rejected as expected"
else
    log_warn "  GET /api/auth/me (no token) - Unexpected: ${ME_NO_TOKEN}"
fi

echo ""
echo ">>> Step 2.4: Test instance endpoints (authenticated)..."

AUTH_HEADER="Authorization: Bearer ${TEST_TOKEN}"

echo "  - GET /api/instances"
INSTANCES_RESPONSE=$(curl -sf -H "${AUTH_HEADER}" http://${SERVER_HOST}:${SERVER_PORT}/api/instances)
if echo "$INSTANCES_RESPONSE" | grep -q '"instances"'; then
    log_info "  GET /api/instances - OK: ${INSTANCES_RESPONSE}"
else
    log_warn "  GET /api/instances - Failed: ${INSTANCES_RESPONSE}"
fi

echo ""
echo "  - POST /api/instances/start"
START_RESPONSE=$(curl -sf -X POST -H "${AUTH_HEADER}" http://${SERVER_HOST}:${SERVER_PORT}/api/instances/start \
    -H "Content-Type: application/json" \
    -d '{"instanceName":"akiba-instance"}')
if echo "$START_RESPONSE" | grep -q '"message"'; then
    log_info "  POST /api/instances/start - OK: ${START_RESPONSE}"
else
    log_warn "  POST /api/instances/start - Failed: ${START_RESPONSE}"
fi

echo ""
echo "  - POST /api/instances/shutdown"
SHUTDOWN_RESPONSE=$(curl -sf -X POST -H "${AUTH_HEADER}" http://${SERVER_HOST}:${SERVER_PORT}/api/instances/shutdown \
    -H "Content-Type: application/json" \
    -d '{"instanceName":"akiba-instance"}')
if echo "$SHUTDOWN_RESPONSE" | grep -q '"message"'; then
    log_info "  POST /api/instances/shutdown - OK: ${SHUTDOWN_RESPONSE}"
else
    log_warn "  POST /api/instances/shutdown - Failed: ${SHUTDOWN_RESPONSE}"
fi

echo ""
echo "  - POST /api/instances/backup"
BACKUP_RESPONSE=$(curl -sf -X POST -H "${AUTH_HEADER}" http://${SERVER_HOST}:${SERVER_PORT}/api/instances/backup \
    -H "Content-Type: application/json" \
    -d '{"instanceName":"akiba-instance","backupName":"test_backup","description":"Test backup via API"}')
if echo "$BACKUP_RESPONSE" | grep -q '"message"'; then
    log_info "  POST /api/instances/backup - OK: ${BACKUP_RESPONSE}"
else
    log_warn "  POST /api/instances/backup - Failed: ${BACKUP_RESPONSE}"
fi

echo ""
echo ">>> Step 2.5: Test workflow endpoints (authenticated)..."

echo "  - POST /api/workflow/start"
WORKFLOW_RESPONSE=$(curl -sf -X POST -H "${AUTH_HEADER}" http://${SERVER_HOST}:${SERVER_PORT}/api/workflow/start \
    -H "Content-Type: application/json" \
    -d '{"instanceName":"akiba-instance","threads":1}')
if echo "$WORKFLOW_RESPONSE" | grep -q '"workflowId"'; then
    WORKFLOW_ID=$(echo "$WORKFLOW_RESPONSE" | grep -o '"workflowId":"[^"]*"' | cut -d'"' -f4)
    log_info "  POST /api/workflow/start - OK: workflowId=${WORKFLOW_ID}"

    sleep 2

    echo "  - GET /api/workflow/status/${WORKFLOW_ID}"
    WORKFLOW_STATUS=$(curl -sf -H "${AUTH_HEADER}" http://${SERVER_HOST}:${SERVER_PORT}/api/workflow/status/${WORKFLOW_ID})
    if echo "$WORKFLOW_STATUS" | grep -q '"status"'; then
        log_info "  GET /api/workflow/status - OK: ${WORKFLOW_STATUS}"
    else
        log_warn "  GET /api/workflow/status - Failed: ${WORKFLOW_STATUS}"
    fi

    echo "  - POST /api/workflow/stop/${WORKFLOW_ID}"
    STOP_WORKFLOW=$(curl -sf -X POST -H "${AUTH_HEADER}" http://${SERVER_HOST}:${SERVER_PORT}/api/workflow/stop/${WORKFLOW_ID})
    if echo "$STOP_WORKFLOW" | grep -q '"message"'; then
        log_info "  POST /api/workflow/stop - OK: ${STOP_WORKFLOW}"
    else
        log_warn "  POST /api/workflow/stop - Failed: ${STOP_WORKFLOW}"
    fi
else
    log_warn "  POST /api/workflow/start - Failed: ${WORKFLOW_RESPONSE}"
fi

echo ""
echo "  - GET /api/workflow/running"
RUNNING_WORKFLOWS=$(curl -sf -H "${AUTH_HEADER}" http://${SERVER_HOST}:${SERVER_PORT}/api/workflow/running)
if echo "$RUNNING_WORKFLOWS" | grep -q '"workflows"'; then
    log_info "  GET /api/workflow/running - OK: ${RUNNING_WORKFLOWS}"
else
    log_warn "  GET /api/workflow/running - Failed: ${RUNNING_WORKFLOWS}"
fi

echo ""
echo "  - GET /api/workflow/history"
WORKFLOW_HISTORY=$(curl -sf -H "${AUTH_HEADER}" http://${SERVER_HOST}:${SERVER_PORT}/api/workflow/history)
if echo "$WORKFLOW_HISTORY" | grep -q '"workflows"'; then
    log_info "  GET /api/workflow/history - OK: ${WORKFLOW_HISTORY}"
else
    log_warn "  GET /api/workflow/history - Failed: ${WORKFLOW_HISTORY}"
fi

echo ""
echo ">>> Step 2.6: Test script endpoints (authenticated)..."

echo "  - POST /api/scripts/run"
SCRIPT_RESPONSE=$(curl -sf -X POST -H "${AUTH_HEADER}" http://${SERVER_HOST}:${SERVER_PORT}/api/scripts/run \
    -H "Content-Type: application/json" \
    -d '{"name":"test_script","code":"echo Hello from Akiba Server! && uname -a"}')
if echo "$SCRIPT_RESPONSE" | grep -q '"scriptId"'; then
    SCRIPT_ID=$(echo "$SCRIPT_RESPONSE" | grep -o '"scriptId":[0-9]*' | cut -d':' -f2)
    log_info "  POST /api/scripts/run - OK: scriptId=${SCRIPT_ID}"

    sleep 2

    echo "  - GET /api/scripts"
    SCRIPTS_LIST=$(curl -sf -H "${AUTH_HEADER}" http://${SERVER_HOST}:${SERVER_PORT}/api/scripts)
    if echo "$SCRIPTS_LIST" | grep -q '"scripts"'; then
        log_info "  GET /api/scripts - OK: found scripts"
    else
        log_warn "  GET /api/scripts - Failed: ${SCRIPTS_LIST}"
    fi

    echo "  - GET /api/scripts/${SCRIPT_ID}"
    SCRIPT_DETAIL=$(curl -sf -H "${AUTH_HEADER}" http://${SERVER_HOST}:${SERVER_PORT}/api/scripts/${SCRIPT_ID})
    if echo "$SCRIPT_DETAIL" | grep -q '"name"'; then
        log_info "  GET /api/scripts/${SCRIPT_ID} - OK: ${SCRIPT_DETAIL}"
    else
        log_warn "  GET /api/scripts/${SCRIPT_ID} - Failed: ${SCRIPT_DETAIL}"
    fi

    echo "  - DELETE /api/scripts/${SCRIPT_ID}"
    DELETE_SCRIPT=$(curl -sf -X DELETE -H "${AUTH_HEADER}" http://${SERVER_HOST}:${SERVER_PORT}/api/scripts/${SCRIPT_ID})
    if echo "$DELETE_SCRIPT" | grep -q '"message"'; then
        log_info "  DELETE /api/scripts/${SCRIPT_ID} - OK: deleted"
    else
        log_warn "  DELETE /api/scripts/${SCRIPT_ID} - Failed: ${DELETE_SCRIPT}"
    fi
else
    log_warn "  POST /api/scripts/run - Failed: ${SCRIPT_RESPONSE}"
fi

echo ""
echo ">>> Step 2.7: Test query endpoint (authenticated)..."

echo "  - POST /api/query (valid SELECT)"
QUERY_RESPONSE=$(curl -sf -X POST -H "${AUTH_HEADER}" http://${SERVER_HOST}:${SERVER_PORT}/api/query \
    -H "Content-Type: application/json" \
    -d '{"sql":"SELECT 1 as id","instanceName":"akiba-instance"}')
if echo "$QUERY_RESPONSE" | grep -q '"columns"'; then
    log_info "  POST /api/query (SELECT) - OK: ${QUERY_RESPONSE}"
else
    log_warn "  POST /api/query (SELECT) - Failed: ${QUERY_RESPONSE}"
fi

echo ""
echo "  - POST /api/query (forbidden INSERT)"
FORBIDDEN_QUERY=$(curl -sf -X POST -H "${AUTH_HEADER}" http://${SERVER_HOST}:${SERVER_PORT}/api/query \
    -H "Content-Type: application/json" \
    -d '{"sql":"INSERT INTO test VALUES (1)","instanceName":"akiba-instance"}')
if echo "$FORBIDDEN_QUERY" | grep -q '"error"'; then
    log_info "  POST /api/query (INSERT blocked) - OK: rejected as expected"
else
    log_warn "  POST /api/query (INSERT blocked) - Unexpected: ${FORBIDDEN_QUERY}"
fi

echo ""
echo "  - POST /api/query (empty SQL)"
EMPTY_QUERY=$(curl -sf -X POST -H "${AUTH_HEADER}" http://${SERVER_HOST}:${SERVER_PORT}/api/query \
    -H "Content-Type: application/json" \
    -d '{"sql":"","instanceName":"akiba-instance"}')
if echo "$EMPTY_QUERY" | grep -q '"error"'; then
    log_info "  POST /api/query (empty) - OK: rejected as expected"
else
    log_warn "  POST /api/query (empty) - Unexpected: ${EMPTY_QUERY}"
fi

echo ""
echo "  - GET /api/query/history"
QUERY_HIST=$(curl -sf -H "${AUTH_HEADER}" http://${SERVER_HOST}:${SERVER_PORT}/api/query/history)
if echo "$QUERY_HIST" | grep -q '"message"'; then
    log_info "  GET /api/query/history - OK: ${QUERY_HIST}"
else
    log_warn "  GET /api/query/history - Failed: ${QUERY_HIST}"
fi

echo ""
echo ">>> Step 2.8: Test file endpoints (authenticated)..."

echo "  - GET /api/files"
FILES_RESPONSE=$(curl -sf -H "${AUTH_HEADER}" http://${SERVER_HOST}:${SERVER_PORT}/api/files)
if echo "$FILES_RESPONSE" | grep -q '"files"'; then
    log_info "  GET /api/files - OK: ${FILES_RESPONSE}"
else
    log_warn "  GET /api/files - Failed: ${FILES_RESPONSE}"
fi

echo ""
echo "  - POST /api/files/import"
IMPORT_RESPONSE=$(curl -sf -X POST -H "${AUTH_HEADER}" http://${SERVER_HOST}:${SERVER_PORT}/api/files/import \
    -H "Content-Type: application/json" \
    -d '{"instanceName":"akiba-instance","files":[]}')
if echo "$IMPORT_RESPONSE" | grep -q '"message"'; then
    log_info "  POST /api/files/import - OK: ${IMPORT_RESPONSE}"
else
    log_warn "  POST /api/files/import - Failed: ${IMPORT_RESPONSE}"
fi

echo ""
echo ">>> Step 2.9: Test logout..."

echo "  - POST /api/auth/logout"
LOGOUT_RESPONSE=$(curl -sf -X POST -H "${AUTH_HEADER}" http://${SERVER_HOST}:${SERVER_PORT}/api/auth/logout)
if echo "$LOGOUT_RESPONSE" | grep -q '"message"'; then
    log_info "  POST /api/auth/logout - OK: ${LOGOUT_RESPONSE}"
else
    log_warn "  POST /api/auth/logout - Failed: ${LOGOUT_RESPONSE}"
fi

echo ""
echo "********************************************************************************"
echo "**************** All Tests Completed *****************************************"
echo "********************************************************************************"
echo ""
log_info "Akiba All-in-One test suite finished!"
echo ""