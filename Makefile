SHELL := /bin/bash

IMAGE ?= docker-ai-cli-agents:test
SMOKE_IMAGE ?=
VERSIONS_FILE ?= versions.json
UPDATE_ARGS ?=
HADOLINT_IMAGE ?= hadolint/hadolint
SHELLCHECK_IMAGE ?= koalaman/shellcheck:stable
YAMLLINT_IMAGE ?= cytopia/yamllint
RUFF_IMAGE ?= ghcr.io/astral-sh/ruff
CODEX_VERSION := $(shell jq -r '.codex.version' versions.json)
CCUSAGE_VERSION := $(shell jq -r '.ccusage.version' versions.json)
CODEX_USAGE_VERSION := $(shell jq -r '.codex_usage.version' versions.json)
REPO_RELEASE_VERSION := $(shell jq -r '.release_version' versions.json)

SHELL_SCRIPTS := \
	scripts/check_versions.sh \
	scripts/run_with_truenas_mounts.sh \
	scripts/smoke_test.sh \
	docker/entrypoint.sh \
	bin/tnclaude \
	bin/tncodex \
	bin/tnccusage \
	bin/tncodexusage

.PHONY: lint hadolint shellcheck yamllint ruff build check-versions update-versions

lint: hadolint shellcheck yamllint ruff
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

ruff:
	docker run --rm \
		--mount "type=bind,src=$(CURDIR),dst=/mnt" \
		-w /mnt \
		"$(RUFF_IMAGE)" check scripts/

build:
	docker build \
		--build-arg CODEX_VERSION="$(CODEX_VERSION)" \
		--build-arg CCUSAGE_VERSION="$(CCUSAGE_VERSION)" \
		--build-arg CODEX_USAGE_VERSION="$(CODEX_USAGE_VERSION)" \
		--build-arg REPO_RELEASE_VERSION="$(REPO_RELEASE_VERSION)" \
		-t "$(IMAGE)" \
		.

check-versions:
	./scripts/check_versions.sh

update-versions:
	python3 scripts/update_versions.py --file "$(VERSIONS_FILE)" $(UPDATE_ARGS)
