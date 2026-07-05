#!/usr/bin/env bash
set -e

# SSH public-key provisioning. SSH_PUBKEY / SSH_PUBKEY2 are set per customer in
# the stack's environment (Portainer). Written fresh each start so the env
# values are the sole source of truth (`.ssh` itself persists in the `home`
# volume) — keys added by hand inside the container do NOT survive a restart;
# add them as SSH_PUBKEY2 (or another env var) instead. Truncate-then-append so
# a start with only SSH_PUBKEY2 set can't append a duplicate to the previous
# file. The strict perms below are mandatory — sshd silently rejects keys
# otherwise.
mkdir -p /home/dev/.ssh
if [ -n "${SSH_PUBKEY:-}${SSH_PUBKEY2:-}" ]; then
  : > /home/dev/.ssh/authorized_keys
  [ -n "${SSH_PUBKEY:-}" ]  && echo "$SSH_PUBKEY"  >> /home/dev/.ssh/authorized_keys
  [ -n "${SSH_PUBKEY2:-}" ] && echo "$SSH_PUBKEY2" >> /home/dev/.ssh/authorized_keys
fi
chmod 700 /home/dev/.ssh
[ -f /home/dev/.ssh/authorized_keys ] && chmod 600 /home/dev/.ssh/authorized_keys

# The `home` volume mounts over /home/dev. A fresh volume is populated from the
# image dir (dev-owned skel), but recreated/older volumes can have root-owned
# paths, and a build-time chown is masked by the mount — so fix ownership at
# runtime. code-server and the CLIs run as `dev` and must own their config.
chown -R dev:dev /home/dev

# Surface env vars to the shells where users actually run things. Compose
# injects vars onto PID 1 (this script) only; neither vector that gives a user a
# shell inherits them: sshd login shells get a fresh environment, and the sudo'd
# code-server below is stripped by sudo's env_reset. Without this:
#   - DEV_PORT is empty, so `process.env.DEV_PORT` is undefined and Vite falls
#     back to its default port (see README "Running dev servers"); and
#   - CLAUDE_CONFIG_DIR is unset, so Claude Code writes its account/onboarding
#     state to ~/.claude.json at the home root (NOT a volume) instead of inside
#     the persisted home volume — wiped every redeploy, forcing a
#     re-login. Pointing it at /home/dev/.claude puts .claude.json next to the
#     already-persisted .credentials.json so the login survives recreations.
#   - DISABLE_AUTOUPDATER is unset, so Claude Code tries to self-update into the
#     root-owned npm global dir (it's installed via `npm install -g` as root),
#     fails, and spams "npm global folder isn't writable". Disable it: claude is
#     updated by rebuilding the image, and any in-container update would land in
#     a non-volume dir and vanish on recreation anyway.
# /etc/profile.d covers SSH login shells; the explicit assignments on the
# code-server exec cover its integrated terminals. Written fresh each start so
# the compose value stays the source of truth.
cat > /etc/profile.d/devbox-env.sh <<EOF
export DEV_PORT=${DEV_PORT:-8081}
export CLAUDE_CONFIG_DIR=/home/dev/.claude
export DISABLE_AUTOUPDATER=1
EOF
chmod 644 /etc/profile.d/devbox-env.sh

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
exec sudo -u dev HOME=/home/dev DEV_PORT="${DEV_PORT:-8081}" CLAUDE_CONFIG_DIR=/home/dev/.claude DISABLE_AUTOUPDATER=1 \
  code-server --bind-addr 0.0.0.0:8443 --auth none /workspace
