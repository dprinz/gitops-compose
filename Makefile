.PHONY: deploy check reconcile test down clean-data

deploy:
	./scripts/deploy.sh

check:
	./scripts/check-drift.sh

reconcile:
	./scripts/reconcile.sh --once

test:
	./tests/run-experiments.sh

down:
	./scripts/compose.sh down --remove-orphans

clean-data:
	@printf 'This deletes the demo volume. Run explicitly:\n  ./scripts/compose.sh down --volumes --remove-orphans\n'
