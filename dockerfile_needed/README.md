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