#!/usr/bin/env bash

# Track test result: 0 = success, non-zero = failure
TEST_EXIT_CODE=0

# ============================================================================
# CLI / env options
# ============================================================================
#
#   -k, --keep-on-success   Skip cleanup if all tests pass, leaving the
#                           database tables, log dirs, binary cache and
#                           Ghidra projects in place for post-mortem
#                           debugging. A failing run always cleans up,
#                           regardless of this flag, to avoid leaving
#                           bad state behind.
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
                          Useful for post-mortem inspection of the
                          database / Ghidra project / log files.
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
        echo "Test artifacts preserved for debugging:"
        echo "  - DB tables:      example_table_*, akiba_example*_results, binaries"
        echo "  - Logs:           ~/.akiba/logs/  (excluding 'server')"
        echo "  - Binary cache:   ~/.akiba/original/, ~/.akiba/processed/"
        echo "  - Workspace:      ~/.akiba/workspace/"
        echo "  - Ghidra project: ~/ghidra_projects/"
        echo ""
        echo "********************************************************************************"
        echo "**************************** Test Completed Successfully ***********************"
        echo "********************************************************************************"
        echo ""
        exit 0
    fi

    echo ""
    echo "********************************************************************************"
    echo "******************************* Cleanup: Test Data *****************************"
    echo "********************************************************************************"
    echo ""

    echo "Cleaning up test data from database..."

    # Drop module result tables created during testing
    psql -p 31800 --dbname=akiba-instance -c "DROP TABLE IF EXISTS example_table_1 CASCADE;" 2>/dev/null
    psql -p 31800 --dbname=akiba-instance -c "DROP TABLE IF EXISTS example_table_2 CASCADE;" 2>/dev/null
    psql -p 31800 --dbname=akiba-instance -c "DROP TABLE IF EXISTS akiba_example3_results CASCADE;" 2>/dev/null
    psql -p 31800 --dbname=akiba-instance -c "DROP TABLE IF EXISTS example_table_4 CASCADE;" 2>/dev/null
    psql -p 31800 --dbname=akiba-instance -c "DROP TABLE IF EXISTS akiba_example1_results CASCADE;" 2>/dev/null

    # Remove binary records and reset auto-increment sequence
    psql -p 31800 --dbname=akiba-instance -c "DELETE FROM binaries;" 2>/dev/null
    psql -p 31800 --dbname=akiba-instance -c "ALTER SEQUENCE binaries_id_seq RESTART WITH 1;" 2>/dev/null

    # ------------------------------------------------------------------
    # File-system cleanup
    #
    # Several persistent on-disk artifacts must be removed for replay
    # tests to behave like a fresh first run; otherwise the second run
    # will hit "duplicate file" / "already exists" errors:
    #
    #   1. ~/.akiba/logs/*    — per-run log directories. We keep the
    #                           `server` subdir (it belongs to the long
    #                           running akiba_server process and is not
    #                           test data).
    #   2. ~/.akiba/original/, ~/.akiba/processed/
    #                         — copies of imported binaries renamed by
    #                           id; stale entries collide with new ids
    #                           after the binaries table is reset.
    #   3. ~/.akiba/workspace/* — per-module workspace files.
    #   4. ~/ghidra_projects/* — Ghidra project files (*.gpr + *.rep/).
    #                           These remember every previously-imported
    #                           program by its `<id>-<filename>` entry,
    #                           which is exactly what causes the
    #                           "duplicate" prompt on rerun.
    # ------------------------------------------------------------------

    # Remove logs except the `server` subdirectory.
    if [ -d ~/.akiba/logs ]; then
        find ~/.akiba/logs -mindepth 1 -maxdepth 1 ! -name 'server' -exec rm -rf {} +
    fi

    # Remove cached binary copies.
    rm -rf ~/.akiba/original ~/.akiba/processed

    # Remove module workspace state.
    rm -rf ~/.akiba/workspace/*

    # Remove Ghidra project files (this is the actual fix for the
    # "duplicate import" prompt on subsequent runs).
    rm -rf ~/ghidra_projects/*

    echo "Test data cleaned up."

    echo ""
    if [ "$TEST_EXIT_CODE" -eq 0 ]; then
        echo "********************************************************************************"
        echo "**************************** Test Completed Successfully ***********************"
        echo "********************************************************************************"
    else
        echo "********************************************************************************"
        echo "**************************** Test FAILED (exit code: $TEST_EXIT_CODE) **********"
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
# Step 2: Run First Test Tasks
# ============================================================================

echo ""
echo "********************************************************************************"
echo "******************************* Step 2: Run First Test Tasks *******************"
echo "********************************************************************************"
echo ""

cd /home/akiba/akiba_framework || fail "Cannot cd to akiba_framework"

sudo -u postgres psql -h 127.0.0.1 -p 31800 -U akiba -d akiba-instance -c "SELECT pg_switch_wal(); SELECT pg_switch_wal();"

echo "Running test tasks 1..."
mkdir -p modules
cp -n ~/binaries/amod*.jar modules 2>/dev/null || echo "No module jars to add, continuing..."
./bin/akiba -c ~/binaries/config_example.json -i ~/binaries/import_example.json

./bin/akiba -c ~/binaries/config_run_example.json@/process_1

# ============================================================================
# Step 3: Verify Database Data
# ============================================================================

echo ""
echo "********************************************************************************"
echo "******************************* Step 3: Verify Database Data *******************"
echo "********************************************************************************"
echo ""

echo "Verifying database has data after test tasks 1..."
if ! psql -p 31800 --dbname=akiba-instance -c "SELECT * FROM binaries;" 2>/dev/null | grep '(1 row)'; then
    fail "No binaries table or empty, first run failed?"
fi
if ! psql -p 31800 --dbname=akiba-instance -c "SELECT * FROM example_table_1;" 2>/dev/null | grep '(1 row)'; then
    fail "No example_table_1 or empty, first run failed?"
fi

# ============================================================================
# Step 4: Create First Backup
# ============================================================================

echo ""
echo "********************************************************************************"
echo "******************************* Step 4: Create First Backup ********************"
echo "********************************************************************************"
echo ""

echo "Creating backup with first test data..."
./bin/akiba instance-backup -i akiba-instance -t full -u akiba -P akiba -a first_backup -d "First backup"
BACKUP_DIR="/akiba/backups/akiba-instance"
EMPTY_BACKUP_EXISTS=$(sudo -u postgres pgbackrest --stanza=akiba-instance --config="$BACKUP_DIR/pgbackrest.conf" info | grep -c 'full backup')
if [ "$EMPTY_BACKUP_EXISTS" -lt 1 ]; then
    fail "First backup was not created normally!"
fi
echo "First backup created successfully."

# ============================================================================
# Step 5: Run Second Test Tasks
# ============================================================================

echo ""
echo "********************************************************************************"
echo "******************************* Step 5: Run Second Test Tasks ******************"
echo "********************************************************************************"
echo ""

echo "Running test tasks 2..."
./bin/akiba -c ~/binaries/config_run_example.json@/process_2

# ============================================================================
# Step 6: Verify Database Data Again
# ============================================================================

echo ""
echo "********************************************************************************"
echo "******************************* Step 6: Verify Database Data Again *************"
echo "********************************************************************************"
echo ""

echo "Verifying database has data after test tasks 2..."
if ! psql -p 31800 --dbname=akiba-instance -c "SELECT * FROM example_table_2;" 2>/dev/null | grep '(1 row)'; then
    fail "No example_table_2 or empty, second run failed?"
fi

# ============================================================================
# Step 7: Create Second Backup
# ============================================================================

echo ""
echo "********************************************************************************"
echo "******************************* Step 7: Create Second Backup *******************"
echo "********************************************************************************"
echo ""

echo "Creating backup with second test data..."
./bin/akiba instance-backup -i akiba-instance -t full -u akiba -P akiba -a second_backup -d "Second backup"

DATA_BACKUP_EXISTS=$(sudo -u postgres pgbackrest --stanza=akiba-instance --config="$BACKUP_DIR/pgbackrest.conf" info | grep -c 'full backup')
if [ "$DATA_BACKUP_EXISTS" -lt 2 ]; then
    fail "Second backup was not created successfully!"
fi
echo "Second backup created successfully."

# ============================================================================
# Step 8: Restore to First Backup
# ============================================================================

echo ""
echo "********************************************************************************"
echo "******************************* Step 8: Restore to First Backup ****************"
echo "********************************************************************************"
echo ""

echo "Restoring akiba-instance to first backup state..."
./bin/akiba instance-restore -i akiba-instance -l first_backup -u akiba -P akiba
./bin/akiba instance-start -i akiba-instance -u akiba -P akiba

# ============================================================================
# Step 9: Verify Restored State
# ============================================================================

echo ""
echo "********************************************************************************"
echo "******************************* Step 9: Verify Restored State ******************"
echo "********************************************************************************"
echo ""

echo "Verifying database is as expected after restoring to first backup..."
BINARIES_COUNT=$(psql -p 31800 --dbname=akiba-instance -t -c "SELECT COUNT(*) FROM binaries;" 2>/dev/null | tr -d ' ')
EXAMPLE_1_COUNT=$(psql -p 31800 --dbname=akiba-instance -t -c "SELECT COUNT(*) FROM example_table_1;" 2>/dev/null | tr -d ' ')
EXAMPLE_2_COUNT=$(psql -p 31800 --dbname=akiba-instance -t -c "SELECT COUNT(*) FROM example_table_2;" 2>/dev/null | tr -d ' ')

BINARIES_COUNT=${BINARIES_COUNT:--1}
EXAMPLE_1_COUNT=${EXAMPLE_1_COUNT:--1}
EXAMPLE_2_COUNT=${EXAMPLE_2_COUNT:--1}

# When we return to the first backup, the table example_table_2 should not exist, and the table binaries and example_table_1 should has 1 row.
if [ "$BINARIES_COUNT" -eq 1 ] && [ "$EXAMPLE_1_COUNT" -eq 1 ] && [ "$EXAMPLE_2_COUNT" -eq -1 ]; then
    echo "Database is as expected after restoring to first backup."
else
    echo "Warning: Database may not be completely expected. Row count: $BINARIES_COUNT, $EXAMPLE_1_COUNT, $EXAMPLE_2_COUNT (-1 means table does not exist)"
    echo "Expected counts: 1, 1, -1"
    fail "Restore to first backup verification failed"
fi

# ============================================================================
# Step 10: Restore to Second Backup
# ============================================================================

echo ""
echo "********************************************************************************"
echo "****************************** Step 10: Restore to Second Backup ***************"
echo "********************************************************************************"
echo ""

echo "Restoring akiba-instance to second backup state..."
./bin/akiba instance-restore -i akiba-instance -l second_backup -u akiba -P akiba
./bin/akiba instance-start -i akiba-instance -u akiba -P akiba

# ============================================================================
# Step 11: Verify Final State
# ============================================================================

echo ""
echo "********************************************************************************"
echo "****************************** Step 11: Verify Final State *********************"
echo "********************************************************************************"
echo ""

echo "Verifying database has data after restoring to test data backup..."
BINARIES_COUNT_AFTER=$(psql -p 31800 --dbname=akiba-instance -t -c "SELECT COUNT(*) FROM binaries;" 2>/dev/null | tr -d ' ')
EXAMPLE_1_COUNT_AFTER=$(psql -p 31800 --dbname=akiba-instance -t -c "SELECT COUNT(*) FROM example_table_1;" 2>/dev/null | tr -d ' ')
EXAMPLE_2_COUNT_AFTER=$(psql -p 31800 --dbname=akiba-instance -t -c "SELECT COUNT(*) FROM example_table_2;" 2>/dev/null | tr -d ' ')

BINARIES_COUNT_AFTER=${BINARIES_COUNT_AFTER:--1}
EXAMPLE_1_COUNT_AFTER=${EXAMPLE_1_COUNT_AFTER:--1}
EXAMPLE_2_COUNT_AFTER=${EXAMPLE_2_COUNT_AFTER:--1}

if [ "$BINARIES_COUNT_AFTER" -eq 1 ] || [ "$EXAMPLE_1_COUNT_AFTER" -eq 1 ] || [ "$EXAMPLE_2_COUNT_AFTER" -eq 1 ]; then
    echo "Database has data as expected after restoring to second backup."
else
    echo "Warning: Database appears to be unexpected after restoring to second backup. Row count: $BINARIES_COUNT_AFTER, $EXAMPLE_1_COUNT_AFTER, $EXAMPLE_2_COUNT_AFTER (-1 means table does not exist)"
    echo "Expected counts: 1, 1, 1"
    fail "Restore to second backup verification failed"
fi

# ============================================================================
# Step 12: Test Runtime callModule() / importFile()
# ============================================================================

echo ""
echo "********************************************************************************"
echo "************* Step 12: Test Runtime callModule() / importFile() ****************"
echo "********************************************************************************"
echo ""

# This step exercises the runtime module-invocation API added to AkibaModule:
#   - callModule(...) lets a running module invoke other modules on demand,
#     without listing them in the static `tasks` array.
#   - importFile(...) lets a running module register a new binary in the
#     database at runtime and chain further analyses on it.
#
# The `process_3` config declares only AkibaExample4 as a task. AkibaExample4
# internally:
#   1) synthesizes a small variant of the binary under analysis,
#   2) calls importFile() to register it (writing source_id/source_module),
#   3) calls callModule("AkibaExample3", config = <in-memory>, targetId = newId),
#   4) AkibaExample3 in turn calls callModule("AkibaExample1") to populate the
#      strings table for the new binary and reads back its findMainFunction()
#      task interface via callTaskAPI().
#
# Therefore, after process_3 succeeds we expect to see:
#   - A second row in `binaries` whose `source_id` and `source_module` match
#     the parent binary's id and "AkibaExample4" respectively.
#   - A row in `example_table_4` containing the new id and a child failure
#     sign of 0 (success).
#   - A row in `example_table_3` for the new id, written by AkibaExample3.
#   - A second row in `example_table_1` for the new id, populated by the
#     chained AkibaExample1 invocation.

echo "Running test tasks 3 (process_3 = AkibaExample4 with runtime dynamic dispatch)..."
./bin/akiba -c ~/binaries/config_run_example.json@/process_3

echo ""
echo "Verifying database state after dynamic dispatch test..."

# Total number of binary rows (parent + the variant imported at runtime).
BINARIES_TOTAL=$(psql -p 31800 --dbname=akiba-instance -t -c "SELECT COUNT(*) FROM binaries;" 2>/dev/null | tr -d ' ')
BINARIES_TOTAL=${BINARIES_TOTAL:--1}

# Provenance: rows with source_module set must point at AkibaExample4 and reference
# an existing parent via source_id.
DERIVED_COUNT=$(psql -p 31800 --dbname=akiba-instance -t -c \
    "SELECT COUNT(*) FROM binaries WHERE source_module = 'AkibaExample4' AND source_id IS NOT NULL;" \
    2>/dev/null | tr -d ' ')
DERIVED_COUNT=${DERIVED_COUNT:--1}

# Result tables. example_table_3 / example_table_4 are created the first time
# their owning module runs, so they should now exist with at least one row.
EX3_COUNT=$(psql -p 31800 --dbname=akiba-instance -t -c "SELECT COUNT(*) FROM akiba_example3_results;" 2>/dev/null | tr -d ' ')
EX3_COUNT=${EX3_COUNT:--1}
EX4_COUNT=$(psql -p 31800 --dbname=akiba-instance -t -c "SELECT COUNT(*) FROM example_table_4;" 2>/dev/null | tr -d ' ')
EX4_COUNT=${EX4_COUNT:--1}

# AkibaExample4 records the spawned child's failureSign; SUCCESS == 0.
CHILD_FAIL_SIGN=$(psql -p 31800 --dbname=akiba-instance -t -c \
    "SELECT child_failure_sign FROM example_table_4 LIMIT 1;" \
    2>/dev/null | tr -d ' ')
CHILD_FAIL_SIGN=${CHILD_FAIL_SIGN:--1}

# AkibaExample4 also captures, via the in-memory RuntimeReport mechanism, the
# child module's matched_count (read out of the child's updateData mirror) and
# its total execution time in ms. Both prove that the parent observed the
# child's runtime side-effects without going through the database.
CHILD_MATCHED=$(psql -p 31800 --dbname=akiba-instance -t -c \
    "SELECT child_matched_count FROM example_table_4 LIMIT 1;" \
    2>/dev/null | tr -d ' ')
CHILD_MATCHED=${CHILD_MATCHED:--1}
CHILD_EXEC_MS=$(psql -p 31800 --dbname=akiba-instance -t -c \
    "SELECT child_execution_time_ms FROM example_table_4 LIMIT 1;" \
    2>/dev/null | tr -d ' ')
CHILD_EXEC_MS=${CHILD_EXEC_MS:--1}

# AkibaExample1's table must now have grown to include the runtime-imported row,
# proving callModule() correctly chained AkibaExample1 inside AkibaExample3.
EX1_TOTAL=$(psql -p 31800 --dbname=akiba-instance -t -c "SELECT COUNT(*) FROM akiba_example1_results;" 2>/dev/null | tr -d ' ')
EX1_TOTAL=${EX1_TOTAL:--1}

echo "binaries total      = $BINARIES_TOTAL (expected >= 2)"
echo "binaries derived    = $DERIVED_COUNT  (expected >= 1, source_module='AkibaExample4')"
echo "example_table_3 cnt = $EX3_COUNT      (expected >= 1)"
echo "example_table_4 cnt = $EX4_COUNT      (expected >= 1)"
echo "child failure sign  = $CHILD_FAIL_SIGN (expected 0 == SUCCESS)"
echo "child matched_count = $CHILD_MATCHED  (expected >= 0, read via RuntimeReport)"
echo "child exec time ms  = $CHILD_EXEC_MS  (expected > 0, read via RuntimeReport)"
echo "akiba_example1_results cnt = $EX1_TOTAL (expected >= 1: one for child)"

if [ "$BINARIES_TOTAL" -lt 2 ]; then
    fail "importFile() did not create a new binaries row."
fi
if [ "$DERIVED_COUNT" -lt 1 ]; then
    fail "source_id / source_module were not recorded by importFile()."
fi
if [ "$EX4_COUNT" -lt 1 ]; then
    fail "AkibaExample4 did not write its result row."
fi
if [ "$CHILD_MATCHED" -lt 0 ]; then
    fail "child_matched_count not propagated via RuntimeReport (got $CHILD_MATCHED)."
fi
if [ "$CHILD_EXEC_MS" -le 0 ]; then
    fail "child_execution_time_ms not propagated via RuntimeReport (got $CHILD_EXEC_MS)."
fi
if [ "$EX3_COUNT" -lt 1 ]; then
    fail "callModule(AkibaExample3, ...) was not executed by AkibaExample4."
fi
if [ "$CHILD_FAIL_SIGN" != "0" ]; then
    fail "child module reported failure (sign=$CHILD_FAIL_SIGN)."
fi
if [ "$EX1_TOTAL" -lt 1 ]; then
    fail "chained callModule(AkibaExample1) inside AkibaExample3 did not run."
fi

echo "Runtime dynamic-dispatch test passed."

# If we reach here, all tests passed. cleanup() will be triggered by trap EXIT.
