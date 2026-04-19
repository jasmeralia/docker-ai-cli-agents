# hadolint ignore=DL3007
FROM ghcr.io/anthropics/claude-code:latest

# hadolint ignore=DL3002
USER root

ARG DEBIAN_FRONTEND=noninteractive
ARG CODEX_NPM_PACKAGE=@openai/codex
ARG CODEX_VERSION=0.0.0
ARG CCUSAGE_NPM_PACKAGE=ccusage
ARG CCUSAGE_VERSION=0.0.0
ARG CODEX_USAGE_NPM_PACKAGE=@ccusage/codex
ARG CODEX_USAGE_VERSION=0.0.0
ARG REPO_RELEASE_VERSION=0.1.0
ARG REPOSITORY_URL=https://github.com/owner/docker-ai-cli-agents
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="docker-ai-cli-agents" \
      org.opencontainers.image.description="Sandboxed AI dev environment with Claude Code, Codex, and Serena MCP for Python and Node.js development." \
      org.opencontainers.image.source="${REPOSITORY_URL}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${REPO_RELEASE_VERSION}" \
      io.github.docker-ai-cli-agents.release-version="${REPO_RELEASE_VERSION}" \
      io.github.docker-ai-cli-agents.codex-version="${CODEX_VERSION}" \
      io.github.docker-ai-cli-agents.ccusage-version="${CCUSAGE_VERSION}" \
      io.github.docker-ai-cli-agents.codex-usage-version="${CODEX_USAGE_VERSION}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        docker.io \
        fd-find \
        python3 \
        python3-pip \
        python3-venv \
        tree \
        wget \
        xz-utils \
        yq \
    && rm -rf /var/lib/apt/lists/*

# Install uv for Serena
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

# Install Serena MCP server
RUN uv tool install -p 3.13 serena-agent@latest --prerelease=allow

# hadolint ignore=DL3016
RUN if [[ "${CODEX_VERSION}" == "0.0.0" || "${CODEX_VERSION}" == "latest" ]]; then \
      npm install -g "${CODEX_NPM_PACKAGE}"; \
    else \
      npm install -g "${CODEX_NPM_PACKAGE}@${CODEX_VERSION}"; \
    fi

# hadolint ignore=DL3016
RUN ccusage_pkg="${CCUSAGE_NPM_PACKAGE}" \
      && if [[ "${CCUSAGE_VERSION}" != "0.0.0" && "${CCUSAGE_VERSION}" != "latest" ]]; then \
        ccusage_pkg="${ccusage_pkg}@${CCUSAGE_VERSION}"; \
      fi \
      && codex_usage_pkg="${CODEX_USAGE_NPM_PACKAGE}" \
      && if [[ "${CODEX_USAGE_VERSION}" != "0.0.0" && "${CODEX_USAGE_VERSION}" != "latest" ]]; then \
        codex_usage_pkg="${codex_usage_pkg}@${CODEX_USAGE_VERSION}"; \
      fi \
      && npm install -g "${ccusage_pkg}" "${codex_usage_pkg}"

COPY docker/entrypoint.sh /usr/local/bin/ai-cli-entrypoint
RUN chmod +x /usr/local/bin/ai-cli-entrypoint

ENV AI_CLI_LOG_LEVEL=info
WORKDIR /workdir
ENTRYPOINT ["/usr/local/bin/ai-cli-entrypoint"]
CMD ["--claude"]
