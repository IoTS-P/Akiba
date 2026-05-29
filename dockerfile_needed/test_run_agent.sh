#!/usr/bin/env bash

echo ""
echo "********************************************************************************"
echo "******** Agent Module Test (AkibaExample5 — Vuln Analysis) ********************"
echo "********************************************************************************"
echo ""

# AkibaExample5 is an AgentModule that uses an LLM to analyze the binary for
# security vulnerabilities. It requires a configured LLM provider and API key.
# If AKIBA_LLM_API_KEY is not set, we skip this test gracefully.

if [ -z "${AKIBA_LLM_API_KEY:-}" ]; then
    echo "AKIBA_LLM_API_KEY is not set — skipping agent module test."
    echo "(Set AKIBA_LLM_API_KEY to enable AkibaExample5 testing.)"
    exit 0
fi

echo ""
echo "********************************************************************************"
echo "******************************* Step 1: Check Database Daemon ******************"
echo "********************************************************************************"
echo ""

echo "Checking if database daemon is running..."
if ! curl -f http://localhost:31777/test; then
    echo "Error: Database daemon is not running or not accessible!"
    exit 1
fi
echo "Database daemon is running normally."

echo ""
echo "********************************************************************************"
echo "******************************* Step 2: Import Binary **************************"
echo "********************************************************************************"
echo ""

cd /home/akiba/akiba_framework || exit 1

sudo -u postgres psql -h 127.0.0.1 -p 31800 -U akiba -d akiba-instance -c "SELECT pg_switch_wal(); SELECT pg_switch_wal();"

echo "Preparing modules and importing binary..."
mkdir -p modules
cp -n ~/binaries/amod*.jar modules 2>/dev/null || echo "No module jars to add, continuing..."
./bin/akiba -c ~/binaries/config_example.json -i ~/binaries/import_example.json

echo ""
echo "********************************************************************************"
echo "******************************* Step 3: Run Agent Module ***********************"
echo "********************************************************************************"
echo ""

echo "Running test tasks 4 (process_4 = AkibaExample5, agent-based vuln analysis)..."
./bin/akiba -c ~/binaries/config_run_example.json@/process_4

echo ""
echo "Verifying database state after agent module test..."

# AkibaExample5 uses @DoNotCreateTable — it does not write to a module
# result table. Instead, all agent activity is recorded in the agent
# session/message tables (created by agent_database_init.sql).
# Verify that at least one agent session was created for this run.
SESSION_COUNT=$(psql -p 31800 --dbname=akiba-instance -t -c \
    "SELECT COUNT(*) FROM agent_sessions WHERE module_name = 'AkibaExample5';" 2>/dev/null | tr -d ' ')
SESSION_COUNT=${SESSION_COUNT:--1}

MESSAGE_COUNT=$(psql -p 31800 --dbname=akiba-instance -t -c \
    "SELECT COUNT(*) FROM agent_messages m JOIN agent_sessions s ON m.session_id = s.id WHERE s.module_name = 'AkibaExample5';" 2>/dev/null | tr -d ' ')
MESSAGE_COUNT=${MESSAGE_COUNT:--1}

echo "agent_sessions (AkibaExample5) = $SESSION_COUNT (expected >= 1)"
echo "agent_messages (AkibaExample5) = $MESSAGE_COUNT (expected >= 1)"

if [ "$SESSION_COUNT" -lt 1 ]; then
    echo "Error: AkibaExample5 did not create an agent session."
    exit 1
fi
if [ "$MESSAGE_COUNT" -lt 1 ]; then
    echo "Error: AkibaExample5 agent session has no messages."
    exit 1
fi

echo "Agent module test passed."

echo ""
echo "********************************************************************************"
echo "******************************* Cleanup: Agent Test Data ***********************"
echo "********************************************************************************"
echo ""

# Remove agent test data generated during this run
echo "Cleaning up agent test data from database..."
psql -p 31800 --dbname=akiba-instance -c \
    "DELETE FROM agent_messages WHERE session_id IN (SELECT id FROM agent_sessions WHERE module_name = 'AkibaExample5');" 2>/dev/null
psql -p 31800 --dbname=akiba-instance -c \
    "DELETE FROM agent_sessions WHERE module_name = 'AkibaExample5';" 2>/dev/null

# Remove binary records imported for this test
psql -p 31800 --dbname=akiba-instance -c "DELETE FROM binaries;" 2>/dev/null

echo "Agent test data cleaned up."

echo ""
echo "********************************************************************************"
echo "******************** Agent Test Completed Successfully *************************"
echo "********************************************************************************"
echo ""
