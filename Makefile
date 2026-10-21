.PHONY: bootstrap lint lint-shell test validate validate-schema

bootstrap:
	./tools/dev/bootstrap-test-tools.sh

validate: validate-schema

validate-schema: bootstrap
	.tools/bats/bin/bats tests/schema/metadata.bats

lint: lint-shell

lint-shell: bootstrap
	.tools/shellcheck-v0.11.0/shellcheck bin/monitorctl lib/core/*.sh lib/adapters/*.sh components/*/hooks/*.sh stacks/*/hooks/*.sh

test: bootstrap
	.tools/bats/bin/bats tests/security tests/schema tests/unit tests/cli tests/components tests/stacks stacks/*/tests
