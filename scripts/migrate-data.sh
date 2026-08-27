#!/bin/sh

set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_docker
prepare_desired_state

case "${1:-status}" in
    status)
        compose exec --no-TTY data sh -c 'cat /data/record.json'
        ;;
    up)
        compose exec --no-TTY data sh -eu -c '
            if grep -Eq "\"schema\":[[:space:]]*2" /data/record.json; then
                echo "data already uses schema 2"
                exit 0
            fi
            grep -Eq "\"schema\":[[:space:]]*1" /data/record.json
            cp /data/record.json /data/record.v1.backup.json
            printf "%s\n" "{\"schema\":2,\"payload\":{\"message\":\"synthetic persistent data\"}}" > /data/record.json.new
            mv /data/record.json.new /data/record.json
            echo "migrated persistent data from schema 1 to schema 2"
        '
        ;;
    restore-v1)
        [ "${ALLOW_DATA_ROLLBACK:-0}" = 1 ] || {
            printf 'refusing data restore; set ALLOW_DATA_ROLLBACK=1 after reviewing the backup\n' >&2
            exit 2
        }
        compose exec --no-TTY data sh -eu -c '
            test -s /data/record.v1.backup.json
            cp /data/record.v1.backup.json /data/record.json.new
            mv /data/record.json.new /data/record.json
            echo "restored schema 1 from the explicit data backup"
        '
        ;;
    *)
        printf 'usage: %s [status | up | restore-v1]\n' "$0" >&2
        exit 2
        ;;
esac
