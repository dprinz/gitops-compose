# Preserved reference experiment result

> This run was recorded on 2026-08-27 before the service-specific desired-state hash
> refactor. The qualitative scenarios remain valid evidence for the companion article,
> but the durations below must not be treated as measurements of the current code.
> Run `./tests/run-experiments.sh` again to generate a fresh `latest.md` from the
> current implementation.

- Run: 20260827T132431Z
- Platform: Darwin arm64
- Docker Desktop: 4.77.0
- Docker Engine: 29.5.3
- Docker Compose: 5.1.4
- Compose project: isolated temporary project
- Baseline commit: `8c49337dbeef8f951784f0598f54659e0ab12315`
- V2 commit: `e1b8a133aaceba91fdebe1d77d9dd895494e973d`
- Broken release commit: `6f227660001f91d0ec13fd4f368b0835fe65c18f`
- Configuration rollback commit: `417ab328048b80fc988d8a4cdbdd69bdd9d65dd4`
- Baseline deploy: healthy
- Normal configuration update: 12s
- Drift detector after stopping `web`: exit 1
- Drift reconciliation: 8s
- Unhealthy deployment: exit 1 after 18s
- Recovery by Git revert: 12s
- Configuration rollback to v1: 12s
- Persistent schema after configuration rollback: 2 (unchanged)
- Final drift check: in sync
- Full log: [run-20260827T132431Z.log](run-20260827T132431Z.log)

The durations above are observations from this historical run, not general guarantees.
