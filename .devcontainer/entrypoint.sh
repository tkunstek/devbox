#!/usr/bin/env bash
set -e

# SSH key setup — drop your laptop's public key into the sshkeys volume once
#mkdir -p /home/dev/.ssh
#touch /home/dev/.ssh/authorized_keys
#chown -R dev:dev /home/dev/.ssh
#chmod 700 /home/dev/.ssh
#chmod 600 /home/dev/.ssh/authorized_keys

# Named volumes (claude-config, codex-config, codeserver-config, vscode-server,
# sshkeys) mount over /home/dev/* as empty root-owned dirs. code-server and the
# CLIs run as `dev`, so fix ownership at runtime — a build-time chown is masked
# by the volume mounts.
chown -R dev:dev /home/dev

# sshd needs host keys; generate if the volume doesn't have them yet
ssh-keygen -A

# Start sshd in the background (key-gated build path)
/usr/sbin/sshd

# code-server in foreground. --auth none is safe ONLY because the 8443
# route sits behind Pocket-ID. Never expose 8443 outside the tunnel.
exec sudo -u dev HOME=/home/dev \
  code-server --bind-addr 0.0.0.0:8443 --auth none /workspace
