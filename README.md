# GitOps-like reconciliation with Docker Compose

This is a small, synthetic experiment for testing which GitOps properties Docker
Compose can provide outside Kubernetes. It consists of two containers, two pinned
multi-platform image digests, tracked configuration, health checks and one named
volume. No production values or real secrets are included.

## Companion article

This repository is the reproducible experiment behind article **#31** on
[systemebene](https://systemebene.house-harkonnen.com/):

**[GitOps für Docker Compose: Was nach dem ersten funktionierenden Setup noch fehlt](https://systemebene.house-harkonnen.com/artikel/31-gitops-fuer-docker-compose)**

The article uses the measured scenarios in this repository to separate three concepts
that are often collapsed into one: declarative desired state, automated deployment and
continuous reconciliation. It also looks at the limits the experiment exposes: a Git
revert can restore configuration, but it does not automatically roll back persistent
data; health checks detect a failed release but do not choose a rollback target; and a
small polling reconciler is useful without becoming a Kubernetes-style controller.

The German article is scheduled for **18 September 2026**. The repository and raw
results are public independently of the article.

The project deliberately distinguishes three things:

1. **Declarative desired state:** `compose.yaml` plus the tracked config, startup
   script and demo secret.
2. **Automated deployment:** `scripts/deploy.sh` applies that state and waits for
   both health checks.
3. **Reconciliation:** `scripts/reconcile.sh --watch 30` repeatedly detects and
   repairs runtime drift. Reconciliation exists only while that process is running.

A webhook that only runs `deploy.sh` is deployment automation, not continuous
reconciliation.

## Stack

| Service | Immutable image | Purpose | Health signal |
|---|---|---|---|
| `web` | `nginx:1.27.5-alpine@sha256:65645c...` | Serves the tracked release response and persistent record | HTTP `/health` returns `ok` |
| `data` | `alpine:3.21.3@sha256:a8560b...` | Initializes and holds a synthetic JSON record in a named volume | secret and schema 1/2 record exist |

The full digests are in `compose.yaml`. A content hash over the desired-state files
is added to both containers as `demo.gitops.desired-state`. The drift checker also
compares runtime status, health, Compose's per-service config hash and verifies that
the runtime image reference contains a digest.

## Requirements

- Docker Engine or Docker Desktop with `docker compose` v2
- Git, `curl`, `tar` and a POSIX-compatible shell
- enough local capacity for two Alpine-based images

The published port binds to `127.0.0.1` only. Override it with `APP_PORT`, for
example `APP_PORT=18080 ./scripts/deploy.sh`.

## Quick start

```sh
./scripts/deploy.sh
curl http://127.0.0.1:8080/
curl http://127.0.0.1:8080/data
./scripts/check-drift.sh
```

Use `scripts/compose.sh` instead of raw `docker compose`; it calculates the desired
state hash and revision required by the Compose labels.

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

See [the latest measured run](results/latest.md) after running the suite. Durations
are observations from that machine and run; they are not timing guarantees.

## Individual scenarios

### Manual runtime drift

```sh
./scripts/compose.sh stop web
./scripts/check-drift.sh       # exits 1 and reports the stopped service
./scripts/reconcile.sh --once  # starts it and waits until healthy
```

For continuous polling reconciliation:

```sh
./scripts/reconcile.sh --watch 30
```

Set `RECONCILE_PULL=1` to run `git pull --ff-only` before each iteration. The
reconciler refuses to pull over tracked local changes. This is a simple pull-based
agent, not a controller with transactions, admission policy or cluster-level APIs.

### Health-check failure and configuration rollback

The test fixture `tests/fixtures/nginx.unhealthy.conf` returns HTTP 503 from
`/health`. Applying it makes `deploy.sh` return non-zero after `HEALTH_TIMEOUT`; the
unhealthy container is left available for inspection. Deployment does not silently
claim success and does not guess a rollback target. Total wall-clock duration also
includes container recreation, dependency checks and Compose overhead, so it can be
longer than the configured health timeout.

In a real clone, use an auditable Git operation to restore the previous desired
state, then deploy it:

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

Reverting Compose or Nginx configuration does not change the named volume. The
reason and the separately guarded demo restore are documented in
[`docs/data-migration.md`](docs/data-migration.md).

## What this can and cannot guarantee

With the polling reconciler running, the demo can detect a missing/stopped/unhealthy
service, a desired-state label mismatch, a Compose config-hash mismatch and a
mutable runtime image reference, then ask Compose to recreate or restart services.
Digest pins prevent a registry tag from silently selecting different bytes.

It does **not** provide atomic multi-service rollout, zero downtime, distributed
locking, policy admission, signed-source verification, automatic rollback choice,
or persistent-data rollback. Anyone with Docker access can also spoof labels or
alter host files; the checker is an experiment, not a security boundary. A stopped
reconciler provides no ongoing convergence. Compose health checks show declared
process health, not business correctness.

Those boundaries are the article's handoff: desired state, deployment automation
and reconciliation are related, but they are not interchangeable.
