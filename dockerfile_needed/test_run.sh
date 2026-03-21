#!/usr/bin/env bash

cd /home/akiba/akiba_framework || exit 1
mkdir modules
cp ~/binaries/amod*.jar modules
./bin/akiba_framework -c ~/binaries/config_example.json -i ~/binaries/import_example.json

./bin/akiba_framework -c ~/binaries/config_run_example.json

psql -p 31800 --dbname=akiba-instance -c "SELECT * FROM binaries;"
psql -p 31800 --dbname=akiba-instance -c "SELECT * FROM example_table;"