#!/bin/sh

set -eu

TESTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SOURCE_ROOT=$(CDPATH= cd -- "$TESTS_DIR/.." && pwd)
RESULTS_DIR=${RESULTS_DIR:-$SOURCE_ROOT/results}
mkdir -p "$RESULTS_DIR"

run_stamp=$(date -u '+%Y%m%dT%H%M%SZ')
log_file="$RESULTS_DIR/run-$run_stamp.log"
latest_file="$RESULTS_DIR/latest.md"
work_base=$(mktemp -d "${TMPDIR:-/tmp}/gitops-compose-experiment.XXXXXX")
demo_root="$work_base/project"
project_name="gitops-compose-test-$$"
test_port=${TEST_APP_PORT:-18080}
cleanup_done=0

log() {
    printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "$log_file"
}

cleanup() {
    [ "$cleanup_done" -eq 0 ] || return 0
    cleanup_done=1
    if [ -x "$demo_root/scripts/compose.sh" ]; then
        (
            cd "$demo_root"
            COMPOSE_PROJECT_NAME="$project_name" APP_PORT="$test_port" \
                ./scripts/compose.sh down --volumes --remove-orphans
        ) >>"$log_file" 2>&1 || true
    fi
    case "$work_base" in
        "${TMPDIR:-/tmp}"/gitops-compose-experiment.*)
            rm -rf -- "$work_base"
            ;;
    esac
    normalized_log="${log_file}.normalized"
    sed 's/[[:space:]]*$//' "$log_file" > "$normalized_log"
    mv "$normalized_log" "$log_file"
}
trap cleanup EXIT INT TERM

fail() {
    log "FAIL $*"
    exit 1
}

run_logged() {
    description=$1
    public_command=$2
    shift 2
    log "BEGIN $description command=$public_command"
    started=$(date +%s)
    set +e
    "$@" >>"$log_file" 2>&1
    result=$?
    set -e
    finished=$(date +%s)
    duration=$((finished - started))
    log "END $description exit=$result duration=${duration}s"
    return "$result"
}

record_state() {
    label=$1
    log "STATE $label"
    (
        cd "$demo_root"
        COMPOSE_PROJECT_NAME="$project_name" APP_PORT="$test_port" ./scripts/compose.sh ps --all
        for service in data web; do
            container_id=$(COMPOSE_PROJECT_NAME="$project_name" APP_PORT="$test_port" ./scripts/compose.sh ps --all --quiet "$service")
            if [ -n "$container_id" ]; then
                docker inspect --format 'service={{index .Config.Labels "com.docker.compose.service"}} status={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} image={{.Config.Image}} desired={{index .Config.Labels "demo.gitops.desired-state"}} revision={{index .Config.Labels "demo.gitops.revision"}}' "$container_id"
            fi
        done
    ) >>"$log_file" 2>&1
}

assert_response() {
    expected=$1
    actual=$(curl --fail --silent --show-error "http://127.0.0.1:$test_port/") || fail "HTTP request failed"
    [ "$actual" = "$expected" ] || fail "expected response '$expected', got '$actual'"
    log "ASSERT response=$actual"
}

assert_schema() {
    expected=$1
    actual=$(
        cd "$demo_root"
        COMPOSE_PROJECT_NAME="$project_name" APP_PORT="$test_port" ./scripts/migrate-data.sh status
    )
    printf '%s\n' "$actual" >>"$log_file"
    printf '%s\n' "$actual" | grep -Eq "\"schema\":[[:space:]]*$expected([,}])" || \
        fail "expected persistent schema $expected"
    log "ASSERT persistent_schema=$expected"
}

mkdir -p "$demo_root"
(
    cd "$SOURCE_ROOT"
    tar --exclude='./.git' --exclude='./results' -cf - .
) | (
    cd "$demo_root"
    tar -xf -
)

chmod +x "$demo_root"/scripts/*.sh "$demo_root"/tests/run-experiments.sh

log "RUN start project=$project_name port=$test_port"
docker version >>"$log_file" 2>&1
docker compose version >>"$log_file" 2>&1
uname -srm >>"$log_file" 2>&1

(
    cd "$demo_root"
    git init -q
    git config user.name 'GitOps Compose Experiment'
    git config user.email 'demo@example.invalid'
    git add .
    git commit -q -m 'baseline: healthy v1 configuration'
)
baseline_commit=$(git -C "$demo_root" rev-parse HEAD)

run_logged "baseline deploy" "./scripts/deploy.sh" env COMPOSE_PROJECT_NAME="$project_name" APP_PORT="$test_port" HEALTH_TIMEOUT=30 "$demo_root/scripts/deploy.sh" || fail "baseline deploy failed"
record_state baseline
assert_response 'gitops-compose release=v1'
assert_schema 1

cp "$demo_root/tests/fixtures/nginx.v2.conf" "$demo_root/config/nginx.conf"
git -C "$demo_root" add config/nginx.conf
git -C "$demo_root" commit -q -m 'release: switch response to v2'
v2_commit=$(git -C "$demo_root" rev-parse HEAD)
run_logged "normal config update" "./scripts/deploy.sh" env COMPOSE_PROJECT_NAME="$project_name" APP_PORT="$test_port" HEALTH_TIMEOUT=30 "$demo_root/scripts/deploy.sh" || fail "v2 deploy failed"
config_update_seconds=$duration
record_state config-v2
assert_response 'gitops-compose release=v2'

run_logged "intentional runtime drift" "./scripts/compose.sh stop web" env COMPOSE_PROJECT_NAME="$project_name" APP_PORT="$test_port" "$demo_root/scripts/compose.sh" stop web || fail "could not create drift"
if run_logged "detect stopped web drift" "./scripts/check-drift.sh" env COMPOSE_PROJECT_NAME="$project_name" APP_PORT="$test_port" "$demo_root/scripts/check-drift.sh"; then
    fail "drift detector incorrectly reported in sync"
else
    drift_exit=$?
fi
[ "$drift_exit" -eq 1 ] || fail "drift detector returned $drift_exit instead of 1"
run_logged "reconcile stopped web" "./scripts/reconcile.sh --once" env COMPOSE_PROJECT_NAME="$project_name" APP_PORT="$test_port" HEALTH_TIMEOUT=30 "$demo_root/scripts/reconcile.sh" --once || fail "reconciliation failed"
drift_recovery_seconds=$duration
record_state reconciled
assert_response 'gitops-compose release=v2'

cp "$demo_root/tests/fixtures/nginx.unhealthy.conf" "$demo_root/config/nginx.conf"
git -C "$demo_root" add config/nginx.conf
git -C "$demo_root" commit -q -m 'experiment: intentional unhealthy release'
bad_commit=$(git -C "$demo_root" rev-parse HEAD)
if run_logged "intentional health-check failure" "HEALTH_TIMEOUT=12 ./scripts/deploy.sh" env COMPOSE_PROJECT_NAME="$project_name" APP_PORT="$test_port" HEALTH_TIMEOUT=12 "$demo_root/scripts/deploy.sh"; then
    fail "unhealthy deployment unexpectedly succeeded"
else
    health_failure_exit=$?
fi
health_failure_seconds=$duration
record_state unhealthy-release

git -C "$demo_root" revert --no-edit "$bad_commit" >>"$log_file" 2>&1
run_logged "recover bad release by Git revert" "git revert <bad-commit> && ./scripts/deploy.sh" env COMPOSE_PROJECT_NAME="$project_name" APP_PORT="$test_port" HEALTH_TIMEOUT=30 "$demo_root/scripts/deploy.sh" || fail "bad-release recovery failed"
health_recovery_seconds=$duration
record_state recovered-v2
assert_response 'gitops-compose release=v2'

run_logged "persistent data migration" "./scripts/migrate-data.sh up" env COMPOSE_PROJECT_NAME="$project_name" APP_PORT="$test_port" "$demo_root/scripts/migrate-data.sh" up || fail "data migration failed"
assert_schema 2

git -C "$demo_root" revert --no-edit "$v2_commit" >>"$log_file" 2>&1
rollback_commit=$(git -C "$demo_root" rev-parse HEAD)
run_logged "configuration rollback to v1" "git revert <v2-commit> && ./scripts/deploy.sh" env COMPOSE_PROJECT_NAME="$project_name" APP_PORT="$test_port" HEALTH_TIMEOUT=30 "$demo_root/scripts/deploy.sh" || fail "configuration rollback failed"
config_rollback_seconds=$duration
record_state rolled-back-config
assert_response 'gitops-compose release=v1'
assert_schema 2

run_logged "final drift check" "./scripts/check-drift.sh" env COMPOSE_PROJECT_NAME="$project_name" APP_PORT="$test_port" "$demo_root/scripts/check-drift.sh" || fail "final state has drift"

cat > "$latest_file" <<EOF
# Latest experiment result

- Run: $run_stamp
- Platform: $(uname -s) $(uname -m)
- Compose project: isolated temporary project
- Baseline commit: \`$baseline_commit\`
- V2 commit: \`$v2_commit\`
- Broken release commit: \`$bad_commit\`
- Configuration rollback commit: \`$rollback_commit\`
- Baseline deploy: healthy
- Normal configuration update: ${config_update_seconds}s
- Drift detector after stopping \`web\`: exit $drift_exit
- Drift reconciliation: ${drift_recovery_seconds}s
- Unhealthy deployment: exit $health_failure_exit after ${health_failure_seconds}s
- Recovery by Git revert: ${health_recovery_seconds}s
- Configuration rollback to v1: ${config_rollback_seconds}s
- Persistent schema after configuration rollback: 2 (unchanged)
- Final drift check: in sync
- Full log: [run-$run_stamp.log](run-$run_stamp.log)

The durations above are observations from this run, not general guarantees.
EOF

log "PASS all experiments completed results=results/latest.md"
