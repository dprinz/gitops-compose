#!/bin/sh

set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

usage() {
    printf 'usage: %s [--once | --watch SECONDS]\n' "$0" >&2
    exit 2
}

mode=once
interval=30
if [ "$#" -eq 0 ]; then
    set -- --once
fi

case "$1" in
    --once)
        [ "$#" -eq 1 ] || usage
        ;;
    --watch)
        [ "$#" -eq 2 ] || usage
        mode=watch
        interval=$2
        case "$interval" in
            ''|*[!0-9]*) usage ;;
        esac
        [ "$interval" -gt 0 ] || usage
        ;;
    *)
        usage
        ;;
esac

pull_if_enabled() {
    [ "${RECONCILE_PULL:-0}" = 1 ] || return 0

    git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
        printf '%s pull skipped: not a Git worktree\n' "$(utc_now)" >&2
        return 2
    }
    [ -z "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=no)" ] || {
        printf '%s pull refused: tracked worktree changes are present\n' "$(utc_now)" >&2
        return 2
    }
    git -C "$ROOT_DIR" pull --ff-only
}

reconcile_once() {
    pull_if_enabled || return $?
    if "$ROOT_DIR/scripts/check-drift.sh"; then
        printf '%s reconcile no-op: already in sync\n' "$(utc_now)"
    else
        printf '%s reconcile applying desired state\n' "$(utc_now)"
        "$ROOT_DIR/scripts/deploy.sh"
        "$ROOT_DIR/scripts/check-drift.sh"
    fi
}

require_docker

if [ "$mode" = once ]; then
    reconcile_once
    exit 0
fi

printf '%s reconcile watch started interval=%ss pull=%s\n' \
    "$(utc_now)" "$interval" "${RECONCILE_PULL:-0}"
while :; do
    if ! reconcile_once; then
        printf '%s reconcile iteration failed; retrying\n' "$(utc_now)" >&2
    fi
    sleep "$interval"
done
