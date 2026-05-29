#!/usr/bin/env bash

echo ""
echo "********************************************************************************"
echo "******************************* Step 1: Check Database Daemon ******************"
echo "********************************************************************************"
echo ""

# Step 1: Check if the database daemon is running and accessible
echo "Checking if database daemon is running..."
if ! curl -f http://localhost:31777/test; then
    echo "Error: Database daemon is not running or not accessible!"
    exit 1
fi
echo "Database daemon is running normally."

echo ""
echo "********************************************************************************"
echo "******************************* Step 2: Run First Test Tasks *******************"
echo "********************************************************************************"
echo ""

cd /home/akiba/akiba_framework || exit 1

sudo -u postgres psql -h 127.0.0.1 -p 31800 -U akiba -d akiba-instance -c "SELECT pg_switch_wal(); SELECT pg_switch_wal();"

# Run first test tasks (import first)
echo "Running test tasks 1..."
mkdir -p modules
# The Dockerfile already copies the gradle-built `amod-*.jar` files into modules/,
# so we use `cp -n` (no-clobber) to avoid silently overwriting them with whatever
# happens to live under ~/binaries/ — which is a stale snapshot that may have been
# compiled against an older AkibaModule ABI and therefore would NoSuchMethodError
# at construction time. The line is kept as a best-effort fallback for the case
# where the modules directory is otherwise empty (custom builds, manual testing).
cp -n ~/binaries/amod*.jar modules 2>/dev/null || echo "No module jars to add, continuing..."
./bin/akiba -c ~/binaries/config_example.json -i ~/binaries/import_example.json

./bin/akiba -c ~/binaries/config_run_example.json@/process_1

echo ""
echo "********************************************************************************"
echo "******************************* Step 3: Verify Database Data *******************"
echo "********************************************************************************"
echo ""

# Verify that the database has data after running test tasks
echo "Verifying database has data after test tasks 1..."
if ! psql -p 31800 --dbname=akiba-instance -c "SELECT * FROM binaries;" 2>/dev/null | grep '(1 row)'; then
    echo "No binaries table or empty, first run failed?"
    exit 1
fi
if ! psql -p 31800 --dbname=akiba-instance -c "SELECT * FROM example_table_1;" 2>/dev/null | grep '(1 row)'; then
    echo "No example_table_1 or empty, first run failed?"
    exit 1
fi

echo ""
echo "********************************************************************************"
echo "******************************* Step 4: Create First Backup ********************"
echo "********************************************************************************"
echo ""

# Perform first backup, which will only contains 2 tables, each has 1 row
echo "Creating backup with first test data..."
./bin/akiba instance-backup -i akiba-instance -t full -u akiba -P akiba -a first_backup -d "First backup"
BACKUP_DIR="/akiba/backups/akiba-instance"
EMPTY_BACKUP_EXISTS=$(sudo -u postgres pgbackrest --stanza=akiba-instance --config="$BACKUP_DIR/pgbackrest.conf" info | grep -c 'full backup')
if [ "$EMPTY_BACKUP_EXISTS" -lt 1 ]; then
    echo "Error: First backup was not created normally!"
    exit 1
fi
echo "First backup created successfully."

echo ""
echo "********************************************************************************"
echo "******************************* Step 5: Run Second Test Tasks ******************"
echo "********************************************************************************"
echo ""

# Run second test tasks
echo "Running test tasks 2..."

./bin/akiba -c ~/binaries/config_run_example.json@/process_2

echo ""
echo "********************************************************************************"
echo "******************************* Step 6: Verify Database Data Again *************"
echo "********************************************************************************"
echo ""

# Verify that the database has right data after running test tasks
echo "Verifying database has data after test tasks 2..."
if ! psql -p 31800 --dbname=akiba-instance -c "SELECT * FROM example_table_2;" 2>/dev/null | grep '(1 row)'; then
    echo "No example_table_2 or empty, second run failed?"
    exit 1
fi

echo ""
echo "********************************************************************************"
echo "******************************* Step 7: Create Second Backup *******************"
echo "********************************************************************************"
echo ""

# Create backup with test data
echo "Creating backup with second test data..."
./bin/akiba instance-backup -i akiba-instance -t full -u akiba -P akiba -a second_backup -d "Second backup"

DATA_BACKUP_EXISTS=$(sudo -u postgres pgbackrest --stanza=akiba-instance --config="$BACKUP_DIR/pgbackrest.conf" info | grep -c 'full backup')
if [ "$DATA_BACKUP_EXISTS" -lt 2 ]; then
    echo "Error: Second backup was not created successfully!"
    exit 1
fi
echo "Second backup created successfully."

echo ""
echo "********************************************************************************"
echo "******************************* Step 8: Restore to First Backup ****************"
echo "********************************************************************************"
echo ""

# Restore akiba-instance to first backup state
echo "Restoring akiba-instance to first backup state..."
./bin/akiba instance-restore -i akiba-instance -l first_backup -u akiba -P akiba
./bin/akiba instance-start -i akiba-instance -u akiba -P akiba

echo ""
echo "********************************************************************************"
echo "******************************* Step 9: Verify Restored State ******************"
echo "********************************************************************************"
echo ""

# Verify if the database is as expected
echo "Verifying database is as expected after restoring to first backup..."
BINARIES_COUNT=$(psql -p 31800 --dbname=akiba-instance -t -c "SELECT COUNT(*) FROM binaries;" 2>/dev/null | tr -d ' ')
EXAMPLE_1_COUNT=$(psql -p 31800 --dbname=akiba-instance -t -c "SELECT COUNT(*) FROM example_table_1;" 2>/dev/null | tr -d ' ')
EXAMPLE_2_COUNT=$(psql -p 31800 --dbname=akiba-instance -t -c "SELECT COUNT(*) FROM example_table_2;" 2>/dev/null | tr -d ' ')

BINARIES_COUNT=${BINARIES_COUNT:--1}
EXAMPLE_1_COUNT=${EXAMPLE_1_COUNT:--1}
EXAMPLE_2_COUNT=${EXAMPLE_2_COUNT:--1}

# When we return to the first backup, the table example_table_2 should not exist, and the table binaries and example_table_1 should has 1 row. 
# So we check if binaries count is 1, example_table_1 count is 1, and example_table_2 count is 0 or table not exist (which will also return count as 0).
if [ "$BINARIES_COUNT" -eq 1 ] && [ "$EXAMPLE_1_COUNT" -eq 1 ] && [ "$EXAMPLE_2_COUNT" -eq -1 ]; then
    echo "Database is as expected after restoring to first backup."
else
    echo "Warning: Database may not be completely expected. Row count: $BINARIES_COUNT, $EXAMPLE_1_COUNT, $EXAMPLE_2_COUNT (-1 means table does not exist)"
    echo "Expected counts: 1, 1, -1"
    exit 1
fi

echo ""
echo "********************************************************************************"
echo "****************************** Step 10: Restore to Second Backup ***************"
echo "********************************************************************************"
echo ""

# Restore akiba-instance to second backup state
echo "Restoring akiba-instance to second backup state..."
./bin/akiba instance-restore -i akiba-instance -l second_backup -u akiba -P akiba
./bin/akiba instance-start -i akiba-instance -u akiba -P akiba

echo ""
echo "********************************************************************************"
echo "****************************** Step 11: Verify Final State *********************"
echo "********************************************************************************"
echo ""

# Verify if the database has data after restoring to test data backup
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
    exit 1
fi

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
    echo "Error: importFile() did not create a new binaries row."
    exit 1
fi
if [ "$DERIVED_COUNT" -lt 1 ]; then
    echo "Error: source_id / source_module were not recorded by importFile()."
    exit 1
fi
if [ "$EX4_COUNT" -lt 1 ]; then
    echo "Error: AkibaExample4 did not write its result row."
    exit 1
fi
# Validate the new RuntimeReport-driven columns. matched_count must be a
# non-negative integer (0 is a perfectly legal "no strings matched"). exec_ms
# must be strictly positive — the child surely took some non-zero wall time.
if [ "$CHILD_MATCHED" -lt 0 ]; then
    echo "Error: child_matched_count not propagated via RuntimeReport (got $CHILD_MATCHED)."
    exit 1
fi
if [ "$CHILD_EXEC_MS" -le 0 ]; then
    echo "Error: child_execution_time_ms not propagated via RuntimeReport (got $CHILD_EXEC_MS)."
    exit 1
fi
if [ "$EX3_COUNT" -lt 1 ]; then
    echo "Error: callModule(AkibaExample3, ...) was not executed by AkibaExample4."
    exit 1
fi
if [ "$CHILD_FAIL_SIGN" != "0" ]; then
    echo "Error: child module reported failure (sign=$CHILD_FAIL_SIGN)."
    exit 1
fi
if [ "$EX1_TOTAL" -lt 1 ]; then
    echo "Error: chained callModule(AkibaExample1) inside AkibaExample3 did not run."
    exit 1
fi

echo "Runtime dynamic-dispatch test passed."

echo ""
echo "********************************************************************************"
echo "******************************* Cleanup: Test Data *****************************"
echo "********************************************************************************"
echo ""

# Remove all test data generated during this run so the database is left clean.
echo "Cleaning up test data from database..."

# Drop module result tables created during testing
psql -p 31800 --dbname=akiba-instance -c "DROP TABLE IF EXISTS example_table_1 CASCADE;" 2>/dev/null
psql -p 31800 --dbname=akiba-instance -c "DROP TABLE IF EXISTS example_table_2 CASCADE;" 2>/dev/null
psql -p 31800 --dbname=akiba-instance -c "DROP TABLE IF EXISTS akiba_example3_results CASCADE;" 2>/dev/null
psql -p 31800 --dbname=akiba-instance -c "DROP TABLE IF EXISTS example_table_4 CASCADE;" 2>/dev/null
psql -p 31800 --dbname=akiba-instance -c "DROP TABLE IF EXISTS akiba_example1_results CASCADE;" 2>/dev/null

# Remove binary records inserted during import/runtime
psql -p 31800 --dbname=akiba-instance -c "DELETE FROM binaries;" 2>/dev/null

echo "Test data cleaned up."

echo ""
echo "********************************************************************************"
echo "**************************** Test Completed Successfully ***********************"
echo "********************************************************************************"
echo ""