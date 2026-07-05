FROM node:20-bookworm

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

# node:20-bookworm already ships a `node` user/group at uid/gid 1000, which
# collides with our target uid/gid. Remove whatever occupies the target
# uid/gid, then create `dev` cleanly. No `|| true` on the create — if user
# creation fails the build MUST fail, instead of silently producing an image
# with no `dev` user (which only crash-loops at runtime).
RUN if getent passwd $USER_UID >/dev/null; then userdel -r "$(getent passwd $USER_UID | cut -d: -f1)" 2>/dev/null || true; fi \
 && if getent group $USER_GID >/dev/null; then groupdel "$(getent group $USER_GID | cut -d: -f1)" 2>/dev/null || true; fi \
 && groupadd --gid $USER_GID $USERNAME \
 && useradd --uid $USER_UID --gid $USER_GID -m --shell /bin/bash $USERNAME \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      git curl wget ca-certificates gnupg less sudo openssh-server \
      bash-completion vim nano \
      iputils-ping dnsutils traceroute net-tools netcat-openbsd \
      jq unzip zip tree rsync htop procps tmux \
 && rm -rf /var/lib/apt/lists/*

# Cache-bust knob for CLI freshness. The RUNs below always fetch "latest", but
# Docker reuses their cached layers as long as the instruction text is
# unchanged — so a rebuild alone does NOT update the CLIs. Bump CLI_REFRESH in
# the Portainer stack env (any new value, e.g. today's date) and redeploy with
# rebuild: changing the ARG invalidates the cache from here down, forcing fresh
# installs of claude/codex/netlify, gh, cloudflared, and supabase.
ARG CLI_REFRESH=0
RUN npm install -g @anthropic-ai/claude-code @openai/codex netlify-cli

RUN curl -fsSL https://code-server.dev/install.sh | sh

# GitHub CLI (official apt repo, arch-aware)
RUN mkdir -p -m 755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# Cloudflare Tunnel client (official apt repo, supports amd64/arm64)
RUN mkdir -p /usr/share/keyrings \
 && curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared bookworm main" \
      > /etc/apt/sources.list.d/cloudflared.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends cloudflared \
 && rm -rf /var/lib/apt/lists/*

# Supabase CLI (release tarball; npm global install is no longer supported)
RUN ARCH="$(dpkg --print-architecture)" \
 && curl -fsSL "https://github.com/supabase/cli/releases/latest/download/supabase_linux_${ARCH}.tar.gz" -o /tmp/supabase.tar.gz \
 && tar -xzf /tmp/supabase.tar.gz -C /usr/local/bin supabase \
 && rm /tmp/supabase.tar.gz \
 && supabase --version

# sshd: keys only, no passwords, no root login
RUN mkdir -p /var/run/sshd \
 && sed -i 's/#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config \
 && sed -i 's/#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
 && sed -i 's/#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

RUN echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME

COPY .devcontainer/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Own /workspace as dev in the image. A fresh (empty) named volume inherits the
# image dir's ownership on first mount, so the workspace volume comes up
# dev-owned instead of root — no runtime chown needed.
RUN mkdir -p /workspace && chown $USERNAME:$USERNAME /workspace

WORKDIR /workspace
