SHELL := /bin/bash

IMAGE ?= docker-ai-cli-agents:test
SMOKE_IMAGE ?=
VERSIONS_FILE ?= versions.json
UPDATE_ARGS ?=
HADOLINT_IMAGE ?= hadolint/hadolint
CODEX_VERSION := $(shell jq -r '.codex.version' versions.json)
CCUSAGE_VERSION := $(shell jq -r '.ccusage.version' versions.json)
CODEX_USAGE_VERSION := $(shell jq -r '.codex_usage.version' versions.json)
CLAUDE_VERSION := $(shell jq -r '.claude.version' versions.json)
REPO_RELEASE_VERSION := $(shell jq -r '.release_version' versions.json)

.PHONY: lint hadolint build check-versions update-versions

lint:
	$(MAKE) hadolint
	./scripts/smoke_test.sh "$(SMOKE_IMAGE)"

hadolint:
	docker run --rm -i "$(HADOLINT_IMAGE)" < Dockerfile

build:
	docker build \
		--build-arg CODEX_VERSION="$(CODEX_VERSION)" \
		--build-arg CCUSAGE_VERSION="$(CCUSAGE_VERSION)" \
		--build-arg CODEX_USAGE_VERSION="$(CODEX_USAGE_VERSION)" \
		--build-arg CLAUDE_VERSION="$(CLAUDE_VERSION)" \
		--build-arg REPO_RELEASE_VERSION="$(REPO_RELEASE_VERSION)" \
		-t "$(IMAGE)" \
		.

check-versions:
	./scripts/check_versions.sh

update-versions:
	python3 scripts/update_versions.py --file "$(VERSIONS_FILE)" $(UPDATE_ARGS)
