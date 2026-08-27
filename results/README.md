# Experiment results

Run `./tests/run-experiments.sh`. It creates:

- `latest.md`: compact outcome and measured durations from the latest run;
- `run-<UTC timestamp>.log`: commands, exit codes, container state and timestamps.

The test uses a temporary Git repository, a unique Compose project and an isolated
named volume. Cleanup removes the test containers and volume. Existing project
containers and data are not touched.
