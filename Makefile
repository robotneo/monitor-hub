.PHONY: bootstrap validate validate-schema

bootstrap:
	./tools/dev/bootstrap-test-tools.sh

validate: validate-schema

validate-schema: bootstrap
	.tools/bats/bin/bats tests/schema/metadata.bats
