# FORGE Agent Container — Base Image
# Extend this Dockerfile for your project's language/tool stack.
#
# Usage:
#   docker build -f .forge/Dockerfile -t forge-agent .
#   podman build -f .forge/Dockerfile -t forge-agent .
#
# This image provides the minimal runtime for FORGE agents:
#   - bash (script execution)
#   - git (worktree operations, diff inspection)
#   - curl (optional — for agent CLIs that need downloads)
#   - jq (optional — for JSON artifact parsing)
#
# To add your AI agent CLI, extend this image:
#   FROM forge-agent:latest
#   RUN npm install -g @anthropic-ai/claude-code  # Example: Claude Code
#   # Or: RUN pip install codex-cli               # Example: Codex

FROM debian:bookworm-slim

LABEL maintainer="FORGE Framework" \
      description="Base image for FORGE multi-agent pipeline" \
      forge.version="004b"

# Avoid interactive prompts during package install
ENV DEBIAN_FRONTEND=noninteractive

# Install minimal dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    git \
    curl \
    ca-certificates \
    jq \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for agent execution
RUN groupadd -r forge && useradd -r -g forge -m -d /home/forge forge

# Set up workspace directory
RUN mkdir -p /workspace && chown forge:forge /workspace
WORKDIR /workspace

# Copy FORGE runtime scripts into the image
COPY .forge/lib/ /opt/forge/lib/
COPY .forge/adapters/ /opt/forge/adapters/
COPY .forge/templates/ /opt/forge/templates/

# Make scripts accessible
ENV FORGE_DIR=/opt/forge
ENV PATH="/opt/forge/bin:${PATH}"

# Switch to non-root user
USER forge

# Default command — overridden by orchestrator
CMD ["bash"]
