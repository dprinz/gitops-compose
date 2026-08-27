#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

: "${COMPOSE_PROJECT_NAME:=gitops-compose}"
: "${APP_PORT:=8080}"
: "${HEALTH_TIMEOUT:=30}"

export COMPOSE_PROJECT_NAME APP_PORT HEALTH_TIMEOUT

utc_now() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

hash_stdin() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        openssl dgst -sha256 | awk '{print $NF}'
    fi
}

hash_files() {
    (
        cd "$ROOT_DIR"
        for desired_file in "$@"; do
            test -f "$desired_file" || {
                printf 'missing desired-state file: %s\n' "$desired_file" >&2
                exit 2
            }
            printf 'file:%s\n' "$desired_file"
            wc -c < "$desired_file"
            cat "$desired_file"
        done
    ) | hash_stdin
}

desired_state_sha() {
    hash_files \
        compose.yaml \
        config/nginx.conf \
        scripts/data-service.sh \
        secrets/demo-token.txt
}

data_desired_state_sha() {
    hash_files \
        compose.yaml \
        scripts/data-service.sh \
        secrets/demo-token.txt
}

web_desired_state_sha() {
    hash_files \
        compose.yaml \
        config/nginx.conf
}

desired_revision() {
    if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        revision=$(git -C "$ROOT_DIR" rev-parse --short=12 HEAD)
        if ! git -C "$ROOT_DIR" diff --quiet -- compose.yaml config scripts/data-service.sh secrets/demo-token.txt || \
           ! git -C "$ROOT_DIR" diff --cached --quiet -- compose.yaml config scripts/data-service.sh secrets/demo-token.txt
        then
            revision="${revision}-dirty"
        fi
        printf '%s\n' "$revision"
    else
        printf 'working-tree\n'
    fi
}

prepare_desired_state() {
    DESIRED_STATE_SHA=$(desired_state_sha)
    DATA_DESIRED_STATE_SHA=$(data_desired_state_sha)
    WEB_DESIRED_STATE_SHA=$(web_desired_state_sha)
    DESIRED_REVISION=$(desired_revision)
    export DESIRED_STATE_SHA DATA_DESIRED_STATE_SHA WEB_DESIRED_STATE_SHA DESIRED_REVISION
}

compose() {
    docker compose \
        --project-name "$COMPOSE_PROJECT_NAME" \
        --file "$ROOT_DIR/compose.yaml" \
        --project-directory "$ROOT_DIR" \
        "$@"
}

require_docker() {
    command -v docker >/dev/null 2>&1 || {
        printf 'docker is required\n' >&2
        exit 2
    }
    docker info >/dev/null 2>&1 || {
        printf 'the Docker daemon is not reachable\n' >&2
        exit 2
    }
    docker compose version >/dev/null 2>&1 || {
        printf 'the docker compose CLI is required\n' >&2
        exit 2
    }
}
