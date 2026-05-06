FROM node:20

# hadolint ignore=DL3002
USER root

ARG DEBIAN_FRONTEND=noninteractive
ARG REPO_RELEASE_VERSION=0.1.0
ARG REPOSITORY_URL=https://github.com/owner/docker-ai-cli-agents
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="docker-ai-cli-agents" \
      org.opencontainers.image.description="Sandboxed AI dev environment with Claude Code, Codex, Serena MCP, and Odoo MCP for Python and Node.js development." \
      org.opencontainers.image.source="${REPOSITORY_URL}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.version="${REPO_RELEASE_VERSION}" \
      io.github.docker-ai-cli-agents.release-version="${REPO_RELEASE_VERSION}"

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

# Install uv for Serena and Odoo MCP
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV SERENA_BIN=/root/.local/bin/serena
ENV UVX_BIN=/root/.local/bin/uvx
ENV PATH="/root/.local/bin:${PATH}"

# Install Serena MCP server from pinned version in requirements.txt
COPY requirements.txt /tmp/requirements.txt
RUN uv tool install -p 3.13 "$(grep '^serena-agent' /tmp/requirements.txt | head -1)" --prerelease=allow \
    && test -x "${SERENA_BIN}" \
    && test -x "${UVX_BIN}"

# Install npm tools from lockfile for reproducible builds
COPY package*.json /opt/npm-tools/
RUN npm ci --prefix /opt/npm-tools
ENV PATH="/opt/npm-tools/node_modules/.bin:${PATH}"

COPY docker/entrypoint.sh /usr/local/bin/ai-cli-entrypoint
RUN chmod +x /usr/local/bin/ai-cli-entrypoint

ENV AI_CLI_LOG_LEVEL=info
WORKDIR /workdir
ENTRYPOINT ["/usr/local/bin/ai-cli-entrypoint"]
CMD ["--claude"]
