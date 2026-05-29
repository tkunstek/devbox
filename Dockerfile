FROM node:20-bookworm

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

RUN groupadd --gid $USER_GID $USERNAME 2>/dev/null || true \
 && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME 2>/dev/null || true \
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
