The example configs below contain placeholders (`<your-database-user>`, `<your-password>`, `<your-instance-name>`): fill them in with a user that the database daemon knows and with an instance that user owns. Akiba ships no default account or instance any more — create the first (administrator) account in the web UI, and create your instance there as well.

Use the commands below to import example elf file into database:

```shell
cd /home/akiba/akiba_framework
./bin/akiba_framework -c /home/akiba/binaries/config_example.json -i /home/akiba/binaries/import_example.json
```

Use the commands below to run an example module on the imported elf file:

```shell
cd /home/akiba/akiba_framework
cp /home/akiba/binaries/amod-AkibaExample1-1.0.jar /home/akiba/akiba_framework/modules/
./bin/akiba_framework -c /home/akiba/binaries/config_run_example.json
```

## Upgrading an older deployment

Databases are created with `OWNER akiba`, so every table the server creates inside one is
owned by akiba as well and its migrations (`ALTER TABLE users ADD COLUMN ...`) just work.
Databases left behind by an image up to 4.3.0 have their tables owned by the postgres
superuser instead — that used to abort start-up with `ERROR: must be owner of table
users`. Container start-up hands those objects over to akiba automatically
(`prepare_database()` in `entrypoint.sh`), so upgrading needs no manual step. The server
also names the exact statement to run if it ever meets a table it does not own.

