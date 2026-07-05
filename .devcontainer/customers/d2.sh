#!/usr/bin/env bash
# d2 customer profile. Runs at build time as root (see Dockerfile). Keep every
# install arch-aware — the target is arm64 (DGX Spark), same as the baked-in
# CLIs. No error masking: if an install fails, the build should fail loudly.
set -euo pipefail

# 1Password CLI (official apt repo, arch-aware)
ARCH="$(dpkg --print-architecture)"
curl -fsSL https://downloads.1password.com/linux/keyrings/1password.asc \
  | gpg --dearmor -o /usr/share/keyrings/1password-archive-keyring.gpg
echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/${ARCH} stable main" \
  > /etc/apt/sources.list.d/1password.list
apt-get update
apt-get install -y --no-install-recommends 1password-cli
rm -rf /var/lib/apt/lists/*
op --version
