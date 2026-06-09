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
 && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      git curl ca-certificates less openssh-server sudo gnupg \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code @openai/codex

RUN curl -fsSL https://code-server.dev/install.sh | sh

# sshd: keys only, no passwords, no root login
RUN mkdir -p /var/run/sshd \
 && sed -i 's/#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config \
 && sed -i 's/#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
 && sed -i 's/#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

RUN echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME

COPY .devcontainer/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace
