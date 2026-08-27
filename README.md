# GitOps-like reconciliation with Docker Compose

This is a small, synthetic experiment for testing which GitOps properties can be
implemented around Docker Compose outside Kubernetes. It consists of two containers,
two pinned multi-platform image digests, tracked configuration, health checks and one
named volume. No production values or real secrets are included.

The project intentionally calls itself **GitOps-like** rather than claiming that
Docker Compose itself is a GitOps system. According to the OpenGitOps principles, a
GitOps-managed system is declarative, versioned and immutable, pulled automatically,
and continuously reconciled. This repository implements those properties only to the
extent described below.

## Companion article

This repository is the reproducible experiment behind article **#31** on
[systemebene](https://systemebene.house-harkonnen.com/):

**[GitOps für Docker Compose: Was nach dem ersten funktionierenden Setup noch fehlt](https://systemebene.house-harkonnen.com/artikel/31-gitops-fuer-docker-compose)**

The article uses the measured scenarios in this repository to separate concepts that
are often collapsed into one: declarative desired state, deployment automation,
drift detection and continuous reconciliation. It also looks at limits exposed by
the experiment: a Git revert can restore configuration, but it does not automatically
roll back persistent data; health checks detect a failed release but do not choose a
rollback target; and a small polling reconciler is useful without becoming a
Kubernetes-style controller.

The German article is scheduled for **18 September 2026**. The repository and raw
results are public independently of the article.

## What is implemented

1. **Declarative desired state:** `compose.yaml` plus tracked configuration, startup
   script and synthetic demo secret.
2. **Versioned and immutable references:** the repository is versioned in Git and
   both container images are pinned by digest.
3. **Deployment automation:** `scripts/deploy.sh` applies the local checkout and waits
   for both health checks.
4. **Drift detection:** `scripts/check-drift.sh` compares the running services with
   the local desired state.
5. **Reconciliation:** `scripts/reconcile.sh --watch 30` repeatedly checks and repairs
   runtime drift against the current local checkout.
6. **Optional pull before reconciliation:** with `RECONCILE_PULL=1`, the reconciler
   first runs `git pull --ff-only`, then compares and applies the resulting local
   desired state.

That distinction matters: `--watch` without `RECONCILE_PULL=1` continuously
reconciles runtime state against the **already local** Git checkout, but it does not
notice remote commits by itself. A webhook that only runs `deploy.sh` is deployment
automation, not continuous reconciliation.

The drift checker also enforces one reproducibility policy: a runtime image reference
must contain a digest. A mutable image reference is reported as `POLICY`, not as
runtime drift.

## Stack

| Service | Immutable image | Purpose | Health signal |
|---|---|---|---|
| `web` | `nginx:1.27.5-alpine@sha256:65645c...` | Serves the tracked release response and persistent record | HTTP `/health` returns `ok` |
| `data` | `alpine:3.21.3@sha256:a8560b...` | Initializes and holds a synthetic JSON record in a named volume | secret and schema 1/2 record exist |

The full digests are in `compose.yaml`. Each service gets its own
`demo.gitops.desired-state` hash over the files that can actually affect that service:

- `web`: `compose.yaml` and `config/nginx.conf`
- `data`: `compose.yaml`, `scripts/data-service.sh` and `secrets/demo-token.txt`

This is deliberately service-specific. An earlier version used one global hash for
both services, which meant an Nginx-only configuration change also recreated the
`data` container. The current model avoids that unnecessary coupling.

The Git revision is logged by the deployment tooling, but is deliberately not part of
the runtime Compose model; a README-only commit should not recreate containers.

The drift checker compares runtime status, health, the service-specific desired-state
label and Compose's per-service config hash. It separately checks that the runtime
image reference is digest-pinned.

## Requirements

- Docker Engine or Docker Desktop
- the `docker compose` CLI with support for `up --wait`, `up --wait-timeout` and
  `config --hash`
- Git, `curl`, `tar` and a POSIX-compatible shell
- enough local capacity for two Alpine-based images

The preserved reference run in `results/` used Docker Desktop 4.77.0, Docker Engine
29.5.3 and Docker Compose 5.1.4 on Darwin/arm64. It was produced before the
service-specific hash refactor described above. Its qualitative scenarios remain the
basis for the article, but its timings must not be treated as measurements of the
current implementation.

The published port binds to `127.0.0.1` only. Override it with `APP_PORT`, for example
`APP_PORT=18080 ./scripts/deploy.sh`.

## Quick start

```sh
./scripts/deploy.sh
curl http://127.0.0.1:8080/
curl http://127.0.0.1:8080/data
./scripts/check-drift.sh
```

Use `scripts/compose.sh` instead of raw `docker compose`; it calculates the desired
state hashes and revision used by the helper scripts.

Stop the stack without deleting its data:

```sh
./scripts/compose.sh down --remove-orphans
```

Deleting the demo volume is intentionally separate and destructive:

```sh
./scripts/compose.sh down --volumes --remove-orphans
```

## Reproduce every experiment

```sh
./tests/run-experiments.sh
```

The runner copies the project to a temporary directory, creates a local Git history
with baseline, update, broken-release and revert commits, and uses a unique Compose
project. It records UTC timestamps, command exit codes, durations, health state,
image references, desired-state labels and assertions in `results/`.

The scenarios are:

1. deploy healthy v1 configuration and schema-1 data;
2. commit and deploy a normal v2 configuration change;
3. stop `web` outside Git, detect drift, then reconcile it;
4. commit a health endpoint returning 503 and observe a failed deployment;
5. recover the bad release with `git revert`;
6. migrate persistent data to schema 2;
7. revert the web configuration to v1 and prove the data remains schema 2.

See [the preserved reference run](results/latest.md). Run the suite again to create a
fresh result for the current implementation.

## Individual scenarios

### Manual runtime drift

```sh
./scripts/compose.sh stop web
./scripts/check-drift.sh       # exits 1 and reports the stopped service
./scripts/reconcile.sh --once  # starts it and waits until healthy
```

For continuous polling reconciliation against the local checkout:

```sh
./scripts/reconcile.sh --watch 30
```

To pull the remote branch before each iteration:

```sh
RECONCILE_PULL=1 ./scripts/reconcile.sh --watch 30
```

The reconciler uses `git pull --ff-only` and refuses to pull over tracked local
changes. This is a deliberately small pull-based agent, not a controller with
transactions, admission policy, distributed locking or cluster-level APIs.

### Health-check failure and configuration rollback

The test fixture `tests/fixtures/nginx.unhealthy.conf` returns HTTP 503 from
`/health`. `deploy.sh` uses `docker compose up --wait --wait-timeout` and therefore
returns non-zero when the project does not become healthy in time. The unhealthy
container is left available for inspection. Deployment does not silently claim
success and does not guess a rollback target.

Total wall-clock duration can be longer than `HEALTH_TIMEOUT` because container
recreation, dependency health and Compose overhead occur around the wait itself. In
the preserved reference run, a 12-second wait timeout resulted in an 18-second total
failed deployment.

Use an auditable Git operation to restore the previous desired state, then deploy it:

```sh
git revert <bad-configuration-commit>
./scripts/deploy.sh
```

### Persistent-data migration

```sh
./scripts/migrate-data.sh status
./scripts/migrate-data.sh up
./scripts/migrate-data.sh status
```

Reverting Compose or Nginx configuration does not change the named volume. The reason
and the separately guarded demo restore are documented in
[`docs/data-migration.md`](docs/data-migration.md).

## What this can and cannot guarantee

With the polling reconciler running, the demo can detect a missing, stopped or
unhealthy service and mismatches in the tracked runtime configuration, then ask
Compose to re-apply the local desired state. Digest pins make the referenced image
content immutable. With `RECONCILE_PULL=1`, the loop also fast-forwards the local
checkout before reconciliation when possible.

It does **not** provide atomic multi-service rollout, zero downtime, distributed
locking, policy admission, signed-source verification, automatic rollback choice or
persistent-data rollback. It also does not make host access a security boundary:
anyone with Docker or filesystem access can interfere with the checker itself or with
state outside its model. A stopped reconciler provides no ongoing convergence, and a
Compose health check represents the health condition defined by this project, not
arbitrary business correctness.

Those boundaries are the point of the experiment: desired state, deployment
automation, drift detection and reconciliation are related, but they are not
interchangeable.
