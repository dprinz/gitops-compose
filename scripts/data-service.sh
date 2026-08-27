#!/bin/sh

set -eu
umask 077

data_file=/data/record.json

if [ ! -f "$data_file" ]; then
    temporary_file=/data/record.json.new
    printf '%s\n' '{"schema":1,"message":"synthetic persistent data"}' > "$temporary_file"
    mv "$temporary_file" "$data_file"
fi

trap 'exit 0' INT TERM
while :; do
    sleep 3600 &
    wait "$!"
done
