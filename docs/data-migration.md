# Persistent-data rollback is a separate operation

The Compose file declares that a named volume exists, but Git does not contain the
volume's bytes. Reverting `compose.yaml` or `config/nginx.conf` therefore cannot
reverse a data migration.

The demo starts with this persistent record:

```json
{"schema":1,"message":"synthetic persistent data"}
```

`scripts/migrate-data.sh up` changes it to schema 2 and stores an explicit schema-1
backup in the same demo volume. The end-to-end experiment then reverts the web
configuration to its v1 Git state and verifies that the volume still contains
schema 2. This is intentional.

A data rollback requires its own compatibility analysis, backup and restore plan.
For this synthetic demo only, the guarded restore is:

```sh
ALLOW_DATA_ROLLBACK=1 ./scripts/migrate-data.sh restore-v1
```

That command is not called by `deploy.sh` or `reconcile.sh`. A real system would
also need tested backups outside the live volume, retention rules, restore-time
objectives and application/version compatibility checks. Git history supplies none
of those guarantees.
