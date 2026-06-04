#!/usr/bin/env bash

# Track test result: 0 = success, non-zero = failure
TEST_EXIT_CODE=0

# ============================================================================
# CLI / env options
# ============================================================================
#
#   -k, --keep-on-success   Skip cleanup if all tests pass, leaving the
#                           agent_sessions/agent_messages tables, log
#                           dirs, binary cache and Ghidra projects in
#                           place for post-mortem debugging. A failing
#                           run always cleans up.
#
# Equivalent env-var: KEEP_ON_SUCCESS=1
# ============================================================================
KEEP_ON_SUCCESS="${KEEP_ON_SUCCESS:-0}"
for arg in "$@"; do
    case "$arg" in
        -k|--keep-on-success) KEEP_ON_SUCCESS=1 ;;
        -h|--help)
            cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -k, --keep-on-success   Do not run cleanup if the test succeeds.
                          Useful for inspecting the agent transcript
                          and session messages after a green run.
                          A failing run always cleans up.
  -h, --help              Show this help and exit.

Environment:
  KEEP_ON_SUCCESS=1       Same as --keep-on-success.
EOF
            exit 0
            ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

# ============================================================================
# Cleanup function — always runs regardless of test success/failure
# ============================================================================
cleanup() {
    if [ "$TEST_EXIT_CODE" -eq 0 ] && [ "$KEEP_ON_SUCCESS" = "1" ]; then
        echo ""
        echo "********************************************************************************"
        echo "**************** Skipping cleanup (--keep-on-success) **************************"
        echo "********************************************************************************"
        echo ""
        echo "Agent test artifacts preserved for debugging:"
        echo "  - DB tables:      agent_sessions, agent_messages, binaries"
        echo "  - Logs:           ~/.akiba/logs/  (excluding 'server')"
        echo "  - Binary cache:   ~/.akiba/original/, ~/.akiba/processed/"
        echo "  - Workspace:      ~/.akiba/workspace/"
        echo "  - Ghidra project: ~/ghidra_projects/"
        echo ""
        echo "********************************************************************************"
        echo "******************** Agent Test Completed Successfully *************************"
        echo "********************************************************************************"
        echo ""
        exit 0
    fi

    echo ""
    echo "********************************************************************************"
    echo "******************************* Cleanup: Agent Test Data ***********************"
    echo "********************************************************************************"
    echo ""

    echo "Cleaning up agent test data from database..."

    # Remove agent messages and sessions
    psql -p 31800 --dbname=akiba-instance -c \
        "DELETE FROM agent_messages WHERE session_id IN (SELECT id FROM agent_sessions WHERE module_name = 'AkibaExample5');" 2>/dev/null
    psql -p 31800 --dbname=akiba-instance -c \
        "DELETE FROM agent_sessions WHERE module_name = 'AkibaExample5';" 2>/dev/null

    # Remove binary records and reset auto-increment sequence
    psql -p 31800 --dbname=akiba-instance -c "DELETE FROM binaries;" 2>/dev/null
    psql -p 31800 --dbname=akiba-instance -c "ALTER SEQUENCE binaries_id_seq RESTART WITH 1;" 2>/dev/null

    # ------------------------------------------------------------------
    # File-system cleanup — see test_run.sh for the full rationale.
    # The Ghidra project removal is what actually prevents the
    # "duplicate import" prompt on rerun. The `server` subdir under
    # ~/.akiba/logs/ is preserved because it belongs to the long
    # running akiba_server process and is not test data.
    # ------------------------------------------------------------------

    # Remove logs except the `server` subdirectory.
    if [ -d ~/.akiba/logs ]; then
        find ~/.akiba/logs -mindepth 1 -maxdepth 1 ! -name 'server' -exec rm -rf {} +
    fi

    # Remove cached binary copies.
    rm -rf ~/.akiba/original ~/.akiba/processed

    # Remove module workspace state.
    rm -rf ~/.akiba/workspace/*

    # Remove Ghidra project files (the actual fix for "duplicate import").
    rm -rf ~/ghidra_projects/*

    echo "Agent test data cleaned up."

    echo ""
    if [ "$TEST_EXIT_CODE" -eq 0 ]; then
        echo "********************************************************************************"
        echo "******************** Agent Test Completed Successfully *************************"
        echo "********************************************************************************"
    else
        echo "********************************************************************************"
        echo "******************** Agent Test FAILED (exit code: $TEST_EXIT_CODE) ************"
        echo "********************************************************************************"
    fi
    echo ""

    exit "$TEST_EXIT_CODE"
}

# Register cleanup to run on EXIT (covers normal exit, errors, signals)
trap cleanup EXIT

# ============================================================================
# Helper: fail with message, set exit code, then let trap handle cleanup
# ============================================================================
fail() {
    echo "FAIL: $1"
    TEST_EXIT_CODE=1
    exit 1
}

# ============================================================================
# Pre-check: API key required
# ============================================================================

echo ""
echo "********************************************************************************"
echo "******** Agent Module Test (AkibaExample5 — Vuln Analysis) ********************"
echo "********************************************************************************"
echo ""

if [ -z "${AKIBA_LLM_API_KEY:-}" ]; then
    echo "AKIBA_LLM_API_KEY is not set — skipping agent module test."
    echo "(Set AKIBA_LLM_API_KEY to enable AkibaExample5 testing.)"
    exit 0
fi

# ============================================================================
# Step 1: Check Database Daemon
# ============================================================================

echo ""
echo "********************************************************************************"
echo "******************************* Step 1: Check Database Daemon ******************"
echo "********************************************************************************"
echo ""

echo "Checking if database daemon is running..."
if ! curl -f http://localhost:31777/test; then
    fail "Database daemon is not running or not accessible!"
fi
echo "Database daemon is running normally."

# ============================================================================
# Step 2: Import Binary
# ============================================================================

echo ""
echo "********************************************************************************"
echo "******************************* Step 2: Import Binary **************************"
echo "********************************************************************************"
echo ""

cd /home/akiba/akiba_framework || fail "Cannot cd to akiba_framework"

sudo -u postgres psql -h 127.0.0.1 -p 31800 -U akiba -d akiba-instance -c "SELECT pg_switch_wal(); SELECT pg_switch_wal();"

echo "Preparing modules and importing binary..."
mkdir -p modules
cp -n ~/binaries/amod*.jar modules 2>/dev/null || echo "No module jars to add, continuing..."
./bin/akiba -c ~/binaries/config_example.json -i ~/binaries/import_example.json

# ============================================================================
# Step 3: Run Agent Module
# ============================================================================

echo ""
echo "********************************************************************************"
echo "******************************* Step 3: Run Agent Module ***********************"
echo "********************************************************************************"
echo ""

echo "Running test tasks 4 (process_4 = AkibaExample5, agent-based vuln analysis)..."
./bin/akiba -c ~/binaries/config_run_example.json@/process_4

# ============================================================================
# Step 4: Verify Agent Results
# ============================================================================

echo ""
echo "********************************************************************************"
echo "******************************* Step 4: Verify Agent Results *******************"
echo "********************************************************************************"
echo ""

echo "Verifying database state after agent module test..."

# AkibaExample5 uses @DoNotCreateTable — it does not write to a module
# result table. Instead, all agent activity is recorded in the agent
# session/message tables (created by agent_database_init.sql).
SESSION_COUNT=$(psql -p 31800 --dbname=akiba-instance -t -c \
    "SELECT COUNT(*) FROM agent_sessions WHERE module_name = 'AkibaExample5';" 2>/dev/null | tr -d ' ')
SESSION_COUNT=${SESSION_COUNT:--1}

MESSAGE_COUNT=$(psql -p 31800 --dbname=akiba-instance -t -c \
    "SELECT COUNT(*) FROM agent_messages m JOIN agent_sessions s ON m.session_id = s.session_id WHERE s.module_name = 'AkibaExample5';" 2>/dev/null | tr -d ' ')
MESSAGE_COUNT=${MESSAGE_COUNT:--1}

echo "agent_sessions (AkibaExample5) = $SESSION_COUNT (expected >= 1)"
echo "agent_messages (AkibaExample5) = $MESSAGE_COUNT (expected >= 1)"

if [ "$SESSION_COUNT" -lt 1 ]; then
    fail "AkibaExample5 did not create an agent session."
fi
if [ "$MESSAGE_COUNT" -lt 1 ]; then
    fail "AkibaExample5 agent session has no messages."
fi

echo "Agent module test passed."

# If we reach here, all tests passed. cleanup() will be triggered by trap EXIT.
