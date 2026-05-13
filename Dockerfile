FROM node:26

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
        ca-certificates \
        curl \
        docker.io \
        fd-find \
        file \
        git \
        gosu \
        jq \
        less \
        procps \
        python3 \
        python3-pip \
        python3-venv \
        ripgrep \
        sqlite3 \
        sudo \
        tree \
        wget \
        xz-utils \
        yq \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
# hadolint ignore=DL3008
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Install uv to /usr/local/bin so it is accessible to any runtime user
ENV SERENA_BIN=/usr/local/bin/serena \
    UVX_BIN=/usr/local/bin/uvx
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh

# Install Serena MCP server from pinned version in requirements.txt;
# tool venv goes to /opt/uv-tools and the wrapper binary to /usr/local/bin.
COPY requirements.txt /tmp/requirements.txt
# UV_PYTHON_INSTALL_DIR keeps the downloaded Python 3.13 interpreter out of
# /root/.local (unreachable by non-root users) and into /opt/uv-python so
# the venv symlink target is world-executable.
RUN UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin UV_PYTHON_INSTALL_DIR=/opt/uv-python \
    uv tool install -p 3.13 "$(grep '^serena-agent' /tmp/requirements.txt | head -1)" --prerelease=allow \
    && chmod -R a+rX /opt/uv-tools /opt/uv-python \
    && test -x "${SERENA_BIN}" \
    && test -x "${UVX_BIN}"

# Install npm tools from lockfile for reproducible builds
COPY package*.json /opt/npm-tools/
RUN npm ci --prefix /opt/npm-tools
ENV PATH="/opt/npm-tools/node_modules/.bin:${PATH}"

# Install Codex plugin for Claude Code; loaded via --plugin-dir to avoid
# path conflicts with the host ~/.claude bind mount.
ARG CODEX_PLUGIN_CC_SHA=807e03ac9d5aa23bc395fdec8c3767500a86b3cf
RUN mkdir -p /opt/claude-plugins/codex \
    && curl -fsSL "https://github.com/openai/codex-plugin-cc/archive/${CODEX_PLUGIN_CC_SHA}.tar.gz" \
      | tar -xzf - --strip-components=1 -C /opt/claude-plugins/codex
ENV CODEX_PLUGIN_DIR=/opt/claude-plugins/codex

COPY docker/entrypoint.sh /usr/local/bin/ai-cli-entrypoint
COPY docker/register_mcp_json.py /usr/local/bin/register-mcp-json
RUN chmod +x /usr/local/bin/ai-cli-entrypoint /usr/local/bin/register-mcp-json

ENV AI_CLI_LOG_LEVEL=info
ENTRYPOINT ["/usr/local/bin/ai-cli-entrypoint"]
CMD ["--claude"]
