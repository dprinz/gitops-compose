#!/bin/sh

set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_docker
prepare_desired_state
exec docker compose \
    --project-name "$COMPOSE_PROJECT_NAME" \
    --file "$ROOT_DIR/compose.yaml" \
    --project-directory "$ROOT_DIR" \
    "$@"
