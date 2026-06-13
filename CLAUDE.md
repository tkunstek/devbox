# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **deployment artifact**, not an application. It builds a Docker image
(`Dockerfile`) and a Compose stack (`docker-compose.yml`) for isolated,
per-customer remote dev environments. There is no build/lint/test step here —
the three files (`Dockerfile`, `docker-compose.yml`, `.devcontainer/entrypoint.sh`)
are the whole codebase. See `README.md` for the user-facing operating guide.

## How changes are deployed and verified

- The stack is deployed by **Portainer from this git repo**, one stack per
  customer, on a DGX Spark (`solstice`, **arm64**).
- The only way a change reaches a running container is: **commit → push to
  `main` → redeploy the stack in Portainer**. Dockerfile changes require a
  **rebuild** (not just recreate).
- There is no Docker daemon on the dev MacBook, so changes **cannot be verified
  locally**. The redeploy on the DGX is the real test — never claim a fix works
  until the user reports the rebuilt container's behavior. Verify with
  `docker ps` (status `Up`, ports mapped) and `docker logs <instance>`.
- Pushing to `main` is guarded by the harness. **Commit locally; the user runs
  the push** (`! git push origin main`).

## Architecture essentials

- **One parameterized service deployed N times.** All customer-specific values
  are env vars with defaults (`INSTANCE`, `SSH_PORT`, `CODE_PORT`, `DEV_PORT`,
  `SSH_PUBKEY`); each must be unique per stack. Isolation comes from Portainer
  namespacing named volumes per stack — there is no per-customer code here.
- **Three volumes, by design.** `home:/home/dev` holds *all* per-tool state
  (Claude/Codex/`gh` logins, code-server + VS Code server, `~/.ssh`,
  `~/.gitconfig`, history) — so a new tool's dotfile persists with no compose
  change. Don't re-split it into per-tool volumes (that was the old layout and
  caused a fix-per-tool treadmill). Only state *outside* `/home/dev` gets its own
  volume: `sshhostkeys:/etc/ssh/keys` (host identity). `workspace:/workspace` is
  separate on purpose so code has an independent lifecycle from config.
- **The container runs as root, then drops to `dev`.** `entrypoint.sh` (PID 1,
  root) provisions SSH host keys + `authorized_keys`, `chown`s `/home/dev`,
  starts `sshd`, then `exec sudo -u dev … code-server`. Anything needing root
  (chown over volume mounts, host-key gen) must happen in the entrypoint, not the
  Dockerfile — volume mounts mask build-time changes under their mount points.

## Non-obvious constraints (each caused a real bug — do not regress)

- **uid/gid 1000 collides** with the `node` user in `node:20-bookworm`. The
  Dockerfile frees 1000 then creates `dev` with **no error masking** — keep it
  that way so user-creation failures break the build instead of crash-looping.
- **Named-volume ownership** is inherited from the image dir at first (empty)
  mount. `/workspace` is `chown`ed to `dev` in the image so fresh volumes come up
  dev-owned; the entrypoint also `chown -R dev:dev /home/dev` every start to fix
  the `home` volume (a build-time chown is masked by the mount).
- **`no-new-privileges` breaks `sudo`** (setuid). It was removed deliberately so
  `dev`'s passwordless sudo works — do not re-add it without removing sudo.
- **SSH host keys** live in the `sshhostkeys` volume (`/etc/ssh/keys`) and `sshd`
  is started with `-h` pointing there, so the host identity survives recreation.
  Don't move host keys back into `/etc/ssh` (not a volume → key churn).
- **`DEV_PORT` must be re-exported to user shells by the entrypoint.** Compose
  injects it onto PID 1 only; sshd login shells start from a clean environment and
  `sudo`'s `env_reset` strips it from the code-server it launches — so a terminal's
  `$DEV_PORT` / `process.env.DEV_PORT` is empty and Vite silently falls back to its
  default port. The entrypoint writes `/etc/profile.d/devbox-env.sh` (SSH shells)
  and passes `DEV_PORT=…` on the `sudo … code-server` exec (its integrated
  terminals). Keep both paths if you add more per-stack vars users need at a shell.
- **Dev servers must bind `0.0.0.0`** and listen on `DEV_PORT`; reach them at
  `solstice.local:DEV_PORT` (or `127.0.0.1:DEV_PORT` via VS Code forward — never
  `localhost`, which resolves to IPv6 `::1` first). Full rationale in `README.md`
  → "Running dev servers".
- **`CLAUDE_CONFIG_DIR=/home/dev/.claude` keeps Claude Code logged in across
  recreations — but only if it reaches the shell that runs `claude`.** Claude's
  OAuth tokens (`~/.claude/.credentials.json`) already sat inside the
  `home` volume, but its account/onboarding state defaults to
  `~/.claude.json` at the home root — not a volume — so it was wiped every redeploy
  and forced a re-login. `CLAUDE_CONFIG_DIR` makes that dir the base for *both*
  files, so `.claude.json` lands in the persisted volume. It must be exported by
  the entrypoint (profile.d + code-server exec, like `DEV_PORT` below) — setting
  it in compose `environment:` does NOT work, because that only reaches PID 1, not
  the user's `claude` process.

## CLIs baked into the image

claude-code, codex, gh, cloudflared, supabase, netlify. CLI installs are
**arch-aware** (apt repos / arch-detected tarball) because the target is arm64;
keep them that way.

claude-code is installed `npm install -g` **as root**, so its global dir isn't
`dev`-writable and its self-updater can't run — it would spam "npm global folder
isn't writable". The entrypoint sets `DISABLE_AUTOUPDATER=1` (delivered to shells
the same way as `DEV_PORT`/`CLAUDE_CONFIG_DIR`). **Claude is updated by rebuilding
the image** (the `npm install -g` pulls latest at build); don't re-enable the
in-container updater — its writes land in a non-volume dir and vanish on recreation.
