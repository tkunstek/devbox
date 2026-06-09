#!/usr/bin/env bash
set -e

# SSH public-key provisioning. SSH_PUBKEY is set per customer in the stack's
# environment (Portainer). Written fresh each start so the env value is the
# source of truth; the sshkeys volume persists host keys and perms. The strict
# perms below are mandatory — sshd silently rejects keys otherwise.
mkdir -p /home/dev/.ssh
if [ -n "${SSH_PUBKEY:-}" ]; then
  echo "$SSH_PUBKEY" > /home/dev/.ssh/authorized_keys
fi
chmod 700 /home/dev/.ssh
[ -f /home/dev/.ssh/authorized_keys ] && chmod 600 /home/dev/.ssh/authorized_keys

# Named volumes (claude-config, codex-config, codeserver-config, vscode-server,
# sshkeys) mount over /home/dev/* as empty root-owned dirs. code-server and the
# CLIs run as `dev`, so fix ownership at runtime — a build-time chown is masked
# by the volume mounts.
chown -R dev:dev /home/dev

# Persistent SSH host keys. /etc/ssh is not a volume, so a fresh container
# (every redeploy/rebuild) would regenerate host keys and trip the client's
# "REMOTE HOST IDENTIFICATION HAS CHANGED" guard. Keep them in the sshhostkeys
# volume so a stack's SSH identity is stable across container recreations.
mkdir -p /etc/ssh/keys
[ -f /etc/ssh/keys/ssh_host_ed25519_key ] || ssh-keygen -q -t ed25519 -f /etc/ssh/keys/ssh_host_ed25519_key -N ''
[ -f /etc/ssh/keys/ssh_host_rsa_key ]     || ssh-keygen -q -t rsa -b 4096 -f /etc/ssh/keys/ssh_host_rsa_key -N ''

# Start sshd in the background using the persisted host keys
/usr/sbin/sshd -h /etc/ssh/keys/ssh_host_ed25519_key -h /etc/ssh/keys/ssh_host_rsa_key

# code-server in foreground. --auth none is safe ONLY because the 8443
# route sits behind Pocket-ID. Never expose 8443 outside the tunnel.
exec sudo -u dev HOME=/home/dev \
  code-server --bind-addr 0.0.0.0:8443 --auth none /workspace
