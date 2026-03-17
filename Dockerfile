FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG NODE_VERSION=24.14.0
ARG CODEX_NPM_PACKAGE=@openai/codex
ARG CODEX_VERSION=0.0.0
ARG CCUSAGE_NPM_PACKAGE=ccusage
ARG CCUSAGE_VERSION=0.0.0
ARG CODEX_USAGE_NPM_PACKAGE=@ccusage/codex
ARG CODEX_USAGE_VERSION=0.0.0
ARG CLAUDE_VERSION=0.0.0
ARG REPO_RELEASE_VERSION=0.1.0
ARG REPOSITORY_URL=https://github.com/owner/docker-ai-cli-agents
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="docker-ai-cli-agents" \
      org.opencontainers.image.description="Docker image bundling Codex CLI and Claude CLI for TrueNAS-friendly developer workflows." \
      org.opencontainers.image.source="${REPOSITORY_URL}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${REPO_RELEASE_VERSION}" \
      io.github.docker-ai-cli-agents.release-version="${REPO_RELEASE_VERSION}" \
      io.github.docker-ai-cli-agents.node-version="${NODE_VERSION}" \
      io.github.docker-ai-cli-agents.codex-version="${CODEX_VERSION}" \
      io.github.docker-ai-cli-agents.ccusage-version="${CCUSAGE_VERSION}" \
      io.github.docker-ai-cli-agents.codex-usage-version="${CODEX_USAGE_VERSION}" \
      io.github.docker-ai-cli-agents.claude-version="${CLAUDE_VERSION}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG TARGETARCH

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        fd-find \
        git \
        gh \
        jq \
        less \
        python3 \
        python3-pip \
        ripgrep \
        tree \
        wget \
        xz-utils \
        yq \
        zsh \
    && rm -rf /var/lib/apt/lists/*

RUN case "${TARGETARCH:-amd64}" in \
      amd64) node_arch="x64" ;; \
      arm64) node_arch="arm64" ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" -o /tmp/node.tar.xz \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
    && rm -f /tmp/node.tar.xz \
    && node --version \
    && npm --version

# hadolint ignore=DL3016
RUN if [[ "${CODEX_VERSION}" == "0.0.0" || "${CODEX_VERSION}" == "latest" ]]; then \
      npm install -g "${CODEX_NPM_PACKAGE}"; \
    else \
      npm install -g "${CODEX_NPM_PACKAGE}@${CODEX_VERSION}"; \
    fi

# hadolint ignore=DL3016
RUN ccusage_package="${CCUSAGE_NPM_PACKAGE}" \
      && if [[ "${CCUSAGE_VERSION}" != "0.0.0" && "${CCUSAGE_VERSION}" != "latest" ]]; then \
        ccusage_package="${ccusage_package}@${CCUSAGE_VERSION}"; \
      fi \
      && codex_usage_package="${CODEX_USAGE_NPM_PACKAGE}" \
      && if [[ "${CODEX_USAGE_VERSION}" != "0.0.0" && "${CODEX_USAGE_VERSION}" != "latest" ]]; then \
        codex_usage_package="${codex_usage_package}@${CODEX_USAGE_VERSION}"; \
      fi \
      && npm install -g "${ccusage_package}" "${codex_usage_package}"

RUN curl -fsSL https://claude.ai/install.sh | bash
RUN install -m 0755 "$(readlink -f /root/.local/bin/claude)" /usr/local/bin/claude

COPY docker/entrypoint.sh /usr/local/bin/ai-cli-entrypoint
RUN chmod +x /usr/local/bin/ai-cli-entrypoint

ENV PATH="/root/.local/bin:${PATH}" \
    AI_CLI_HOME=/var/lib/ai-cli-home \
    AI_CLI_LOG_LEVEL=info

WORKDIR /workdir

ENTRYPOINT ["/usr/local/bin/ai-cli-entrypoint"]
CMD ["--codex"]
