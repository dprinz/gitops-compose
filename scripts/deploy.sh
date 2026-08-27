#!/bin/sh

set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_docker
prepare_desired_state

printf '%s deploy start revision=%s desired_state=%s\n' "$(utc_now)" "$DESIRED_REVISION" "$DESIRED_STATE_SHA"

compose up \
    --detach \
    --pull missing \
    --remove-orphans \
    --wait \
    --wait-timeout "$HEALTH_TIMEOUT"

printf '%s deploy healthy revision=%s desired_state=%s\n' "$(utc_now)" "$DESIRED_REVISION" "$DESIRED_STATE_SHA"
compose ps
