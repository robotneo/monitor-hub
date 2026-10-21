.PHONY: bootstrap lint lint-shell test validate validate-schema validate-repository smoke

bootstrap:
	./tools/dev/bootstrap-test-tools.sh

validate: validate-schema validate-repository

validate-schema: bootstrap
	.tools/bats/bin/bats tests/schema/metadata.bats

validate-repository: bootstrap
	./tools/dev/validate-repository.sh

lint: lint-shell

lint-shell: bootstrap
	.tools/shellcheck-v0.11.0/shellcheck bin/monitorctl lib/core/*.sh lib/adapters/*.sh components/*/hooks/*.sh stacks/*/hooks/*.sh

test: bootstrap
	.tools/bats/bin/bats tests/security tests/schema tests/unit tests/cli tests/components tests/stacks tests/acceptance stacks/*/tests

smoke:
	./tools/dev/compose-smoke.sh
