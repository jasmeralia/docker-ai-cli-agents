FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG CODEX_NPM_PACKAGE=@openai/codex
ARG CODEX_VERSION=0.0.0
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
      io.github.docker-ai-cli-agents.codex-version="${CODEX_VERSION}" \
      io.github.docker-ai-cli-agents.claude-version="${CLAUDE_VERSION}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

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
        nodejs \
        npm \
        python3 \
        python3-pip \
        ripgrep \
        tree \
        wget \
        yq \
        zsh \
    && rm -rf /var/lib/apt/lists/*

RUN if [[ "${CODEX_VERSION}" == "0.0.0" || "${CODEX_VERSION}" == "latest" ]]; then \
      npm install -g "${CODEX_NPM_PACKAGE}"; \
    else \
      npm install -g "${CODEX_NPM_PACKAGE}@${CODEX_VERSION}"; \
    fi

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
