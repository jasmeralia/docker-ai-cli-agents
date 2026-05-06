SHELL := /bin/bash

IMAGE ?= docker-ai-cli-agents:test
SMOKE_IMAGE ?=
HADOLINT_IMAGE ?= hadolint/hadolint
SHELLCHECK_IMAGE ?= koalaman/shellcheck:stable
YAMLLINT_IMAGE ?= cytopia/yamllint
REPO_RELEASE_VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0")

SHELL_SCRIPTS := \
	scripts/run_with_truenas_mounts.sh \
	scripts/smoke_test.sh \
	docker/entrypoint.sh \
	bin/tnclaude \
	bin/tncodex \
	bin/tnccusage \
	bin/tncodexusage

.PHONY: lint hadolint shellcheck yamllint build

lint: hadolint shellcheck yamllint
	./scripts/smoke_test.sh "$(SMOKE_IMAGE)"

hadolint:
	docker run --rm -i "$(HADOLINT_IMAGE)" < Dockerfile

shellcheck:
	docker run --rm \
		--mount "type=bind,src=$(CURDIR),dst=/mnt" \
		-w /mnt \
		"$(SHELLCHECK_IMAGE)" $(SHELL_SCRIPTS)

yamllint:
	docker run --rm \
		--mount "type=bind,src=$(CURDIR),dst=/mnt" \
		-w /mnt \
		"$(YAMLLINT_IMAGE)" .github/workflows/

build:
	docker build \
		--build-arg REPO_RELEASE_VERSION="$(REPO_RELEASE_VERSION)" \
		-t "$(IMAGE)" \
		.
