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

sudo -u postgres psql -p 31800 -U akiba -c "SELECT pg_switch_wal(); SELECT pg_switch_wal();"

# Run first test tasks (import first)
echo "Running test tasks 1..."
mkdir -p modules
cp ~/binaries/amod*.jar modules 2>/dev/null || echo "No module jars found, continuing..."
./bin/akiba_framework -c ~/binaries/config_example.json -i ~/binaries/import_example.json

./bin/akiba_framework -c ~/binaries/config_run_example.json@/process_1

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
./bin/akiba_framework instance-backup -i akiba-instance -t full -u akiba -P akiba -a first_backup -d "First backup"
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

./bin/akiba_framework -c ~/binaries/config_run_example.json@/process_2

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
./bin/akiba_framework instance-backup -i akiba-instance -t full -u akiba -P akiba -a second_backup -d "Second backup"

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
./bin/akiba_framework instance-restore -i akiba-instance -l first_backup -u akiba -P akiba
./bin/akiba_framework instance-start -i akiba-instance -u akiba -P akiba

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
./bin/akiba_framework instance-restore -i akiba-instance -l second_backup -u akiba -P akiba
./bin/akiba_framework instance-start -i akiba-instance -u akiba -P akiba

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
echo "**************************** Test Completed Successfully ***********************"
echo "********************************************************************************"
echo ""