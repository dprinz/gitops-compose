#!/bin/sh

set -eu
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_docker
prepare_desired_state

drift_count=0
policy_count=0
expected_services=$(compose config --services)

for service in $expected_services; do
    container_id=$(compose ps --all --quiet "$service")
    if [ -z "$container_id" ]; then
        printf 'DRIFT service=%s reason=missing-container\n' "$service"
        drift_count=$((drift_count + 1))
        continue
    fi

    status=$(docker inspect --format '{{.State.Status}}' "$container_id")
    if [ "$status" != running ]; then
        printf 'DRIFT service=%s reason=status expected=running actual=%s\n' "$service" "$status"
        drift_count=$((drift_count + 1))
    fi

    health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container_id")
    if [ "$health" != healthy ]; then
        printf 'DRIFT service=%s reason=health expected=healthy actual=%s\n' "$service" "$health"
        drift_count=$((drift_count + 1))
    fi

    case "$service" in
        data) expected_desired_hash=$DATA_DESIRED_STATE_SHA ;;
        web) expected_desired_hash=$WEB_DESIRED_STATE_SHA ;;
        *)
            printf 'POLICY service=%s reason=unknown-service\n' "$service"
            policy_count=$((policy_count + 1))
            continue
            ;;
    esac

    actual_hash=$(docker inspect --format '{{index .Config.Labels "demo.gitops.desired-state"}}' "$container_id")
    if [ "$actual_hash" != "$expected_desired_hash" ]; then
        printf 'DRIFT service=%s reason=desired-state-label expected=%s actual=%s\n' \
            "$service" "$expected_desired_hash" "${actual_hash:-missing}"
        drift_count=$((drift_count + 1))
    fi

    expected_config_hash=$(compose config --hash "$service" | awk -v name="$service" '$1 == name { print $2 }')
    actual_config_hash=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.config-hash"}}' "$container_id")
    if [ -z "$expected_config_hash" ] || [ "$actual_config_hash" != "$expected_config_hash" ]; then
        printf 'DRIFT service=%s reason=compose-config-hash expected=%s actual=%s\n' \
            "$service" "${expected_config_hash:-missing}" "${actual_config_hash:-missing}"
        drift_count=$((drift_count + 1))
    fi

    actual_image=$(docker inspect --format '{{.Config.Image}}' "$container_id")
    case "$actual_image" in
        *@sha256:*) ;;
        *)
            printf 'POLICY service=%s reason=mutable-image-reference actual=%s\n' "$service" "$actual_image"
            policy_count=$((policy_count + 1))
            ;;
    esac
done

if [ "$drift_count" -gt 0 ] || [ "$policy_count" -gt 0 ]; then
    printf 'OUT_OF_SYNC drift=%s policy=%s desired_state=%s\n' \
        "$drift_count" "$policy_count" "$DESIRED_STATE_SHA"
    exit 1
fi

printf 'IN_SYNC services=%s desired_state=%s revision=%s\n' \
    "$(printf '%s\n' "$expected_services" | wc -l | tr -d ' ')" \
    "$DESIRED_STATE_SHA" \
    "$DESIRED_REVISION"
