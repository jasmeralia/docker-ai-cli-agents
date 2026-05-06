SHELL := /bin/bash

IMAGE ?= docker-ai-cli-agents:test
SMOKE_IMAGE ?=
HADOLINT_IMAGE ?= hadolint/hadolint
SHELLCHECK_IMAGE ?= koalaman/shellcheck:stable
YAMLLINT_IMAGE ?= cytopia/yamllint
RUFF_IMAGE ?= ghcr.io/astral-sh/ruff
MYPY_IMAGE ?= python:3.13-slim
REPO_RELEASE_VERSION := $(shell git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0")

PYTHON_SCRIPTS := docker/register_mcp_json.py

SHELL_SCRIPTS := \
	scripts/run_with_truenas_mounts.sh \
	scripts/smoke_test.sh \
	docker/entrypoint.sh \
	bin/tnclaude \
	bin/tnclaude-yolo \
	bin/tncodex \
	bin/tncodex-yolo \
	bin/tnccusage \
	bin/tncodexusage

.PHONY: lint hadolint shellcheck yamllint ruff mypy pylint build

lint: hadolint shellcheck yamllint ruff mypy pylint
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
		"$(RUFF_IMAGE)" check $(PYTHON_SCRIPTS)

mypy:
	docker run --rm \
		--mount "type=bind,src=$(CURDIR),dst=/mnt" \
		-w /mnt \
		"$(MYPY_IMAGE)" sh -c "pip install mypy -q --root-user-action=ignore && mypy $(PYTHON_SCRIPTS)"

pylint:
	docker run --rm \
		--mount "type=bind,src=$(CURDIR),dst=/mnt" \
		-w /mnt \
		"$(MYPY_IMAGE)" sh -c "pip install pylint -q --root-user-action=ignore && pylint $(PYTHON_SCRIPTS)"

build:
	docker build \
		--build-arg REPO_RELEASE_VERSION="$(REPO_RELEASE_VERSION)" \
		-t "$(IMAGE)" \
		.
