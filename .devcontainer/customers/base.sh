#!/usr/bin/env bash
# Base customer profile — the default (CUSTOMER=base) for any stack with no
# bespoke tooling. Intentionally a no-op. Every other customer script should
# do only what that customer needs on top of this baseline.
set -euo pipefail

echo "customer profile: base (no extra tooling)"
