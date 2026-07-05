# devbox

A template for **isolated, per-customer remote development environments** running
as Docker containers on a DGX Spark (`solstice`, arm64) and deployed through
Portainer from this git repository.

Each customer gets their own container with their own code, their own Claude /
Codex subscription login, and their own SSH identity. You edit from a MacBook
(VS Code Remote-SSH) or an iPad (code-server in the browser).

---

## Architecture

- **One Portainer stack per customer**, all deployed from this same git repo.
  Portainer namespaces volumes per stack (`<stack>_workspace`, etc.), so each
  customer's code and credentials are isolated automatically.
- The image (`Dockerfile`) is based on `node:20-bookworm` and runs as a non-root
  `dev` user (uid/gid 1000). It bundles dev tooling and CLIs (see below).
- `entrypoint.sh` provisions SSH, starts `sshd`, and runs **code-server** in the
  foreground on port 8443.

### Per-customer configuration

Everything customer-specific is an environment variable, set per stack in
Portainer (**Stacks → \<stack\> → Environment variables**). See `.env.example`.

| Var | Purpose | Must be unique per stack |
|-----|---------|--------------------------|
| `INSTANCE` | container name + hostname | yes |
| `SSH_PORT` | host port → container 22 | yes |
| `CODE_PORT` | host port → code-server 8443 | yes |
| `DEV_PORT` | host port → app dev server | yes |
| `SSH_PUBKEY` | your laptop's public key, injected into `authorized_keys` | no |
| `SSH_PUBKEY2` | optional second public key (another machine), appended to `authorized_keys` | no |
| `CLI_REFRESH` | build-cache bust: bump to any new value + rebuild to update the baked-in CLIs | no |

Suggested scheme:

| Customer | INSTANCE | SSH_PORT | CODE_PORT | DEV_PORT |
|----------|----------|----------|-----------|----------|
| acme     | acme     | 2222     | 8443      | 8081     |
| globex   | globex   | 2223     | 8444      | 8082     |
| initech  | initech  | 2224     | 8445      | 8083     |
| umbrella | umbrella | 2225     | 8446      | 8084     |

### Persistent volumes (per stack)

| Volume | Mount | Holds |
|--------|-------|-------|
| `workspace` | `/workspace` | the customer's code |
| `home` | `/home/dev` | everything per-tool: Claude / Codex / `gh` logins, code-server + VS Code server state, `~/.ssh`, `~/.gitconfig`, shell history |
| `sshhostkeys` | `/etc/ssh/keys` | stable SSH host identity (lives outside `/home/dev`) |

A single `home` volume means a new tool's login or dotfile persists with **no
compose change** — it just lands under `/home/dev`. Only things *outside*
`/home/dev` (the SSH host identity) need their own volume. `workspace` is kept
separate on purpose so customer code has an independent lifecycle from config.

---

## Deploying a new customer

1. In Portainer, **Add stack** → from this git repo.
2. Set the env vars (unique `INSTANCE` / `SSH_PORT` / `CODE_PORT` / `DEV_PORT`,
   plus your `SSH_PUBKEY`).
3. Deploy.
4. SSH in (see below), `git clone` the customer's repo into `/workspace`, and run
   `claude` / `codex` once to log into **that customer's** subscription. The
   login persists in that stack's isolated volumes.

---

## Updating the stacks

Auto-deploy is set up: a **push to `main` fires a Portainer webhook** that
redeploys the stacks from this repo — no manual redeploy needed. Commit, push,
and the running containers pick up the change.

> Dockerfile changes (image contents — installed CLIs, the entrypoint) need a
> **rebuild**, not just a recreate. Compose/env-only changes recreate fine.
> Confirm the webhook rebuilds the image for Dockerfile changes; if not, trigger
> a rebuild for those in Portainer.

### Updating the baked-in CLIs (claude, codex, gh, …)

A rebuild alone does **not** refresh the CLIs: the install steps always fetch
"latest", but Docker reuses their cached layers because the Dockerfile text is
unchanged. To pull current versions, bump `CLI_REFRESH` in the stack's
environment variables (any new value — today's date works), then redeploy
**with re-build enabled**. The changed build arg invalidates the cache from the
CLI installs down, so claude-code, codex, netlify, gh, cloudflared and supabase
all reinstall at their latest versions.

---

## Connecting

### MacBook — VS Code Remote-SSH (primary)

Add to `~/.ssh/config` (one block per customer, varying `Port`):

```
Host momentum
  HostName solstice.local
  Port 2222
  User dev
  IdentityFile ~/.ssh/id_ed25519
```

Then **Remote-SSH: Connect to Host → momentum**. Connect as user `dev` (not your
Mac username).

### iPad — code-server (browser)

Open code-server at your `CODE_PORT` front door in the browser. code-server runs
inside the container and gives you the same editor.

> ⚠️ The entrypoint runs code-server with `--auth none`. That is only safe
> because it is meant to sit behind an authenticating reverse proxy (Pocket-ID /
> Cloudflare Zero Trust). Do not expose `CODE_PORT` to an untrusted network
> without that front door.

---

## Running dev servers (read this)

This is the part that is non-obvious. The rules:

1. **Bind the dev server to `0.0.0.0`.** Defaults that bind `localhost` often
   resolve to IPv6 `::1` only inside the container, which neither VS Code
   forwarding (IPv4) nor the published port can reach. Vite: `server.host: true`.
2. **Listen on `DEV_PORT`.** It's published host↔container and passed in as
   `process.env.DEV_PORT`, so the app is reachable at `solstice.local:DEV_PORT`.
3. **Allow the host.** Vite blocks unknown `Host` headers — set
   `server.allowedHosts: true` (or list `solstice.local`).
4. **Keep `base` at `/`.** Don't use code-server's `/proxy` path for web apps;
   the published port avoids all base-path/HMR pain.

Minimal Vite config:

```ts
export default defineConfig({
  server: {
    host: true,                                  // 0.0.0.0
    port: Number(process.env.DEV_PORT) || 8081,
    strictPort: true,
    allowedHosts: true,
  },
})
```

How to reach a running dev server:

| From | URL |
|------|-----|
| any device on the network | `http://solstice.local:DEV_PORT` |
| MacBook (VS Code forward) | `http://127.0.0.1:DEV_PORT` — use `127.0.0.1`, **not** `localhost` (macOS tries IPv6 `::1` first) |
| iPad browser | `http://solstice.local:DEV_PORT` |

HMR/live-reload works with no extra config because the websocket connects back to
the same `host:port` the page loaded from.

---

## Bundled tooling

Node 20, `git`, `curl`, `wget`, `jq`, `unzip`, `rsync`, `tree`, `htop`, `vim`,
`nano`, networking/diagnostic tools (`ping`, `dig`, `traceroute`, `nc`, …), and
the CLIs: **claude-code**, **codex**, **gh**, **cloudflared**, **supabase**,
**netlify**. The `dev` user has passwordless `sudo`, so additional packages can
be installed at runtime (`sudo apt-get install …`).

---

## Isolation note

These are containers sharing the host kernel and Docker daemon, and `dev` has
passwordless `sudo`. This isolates **your** customers' code and credentials from
each other; it is **not** a hardened boundary against a malicious occupant of a
container.

---

## Troubleshooting

- **"Remote host key has changed / port forwarding disabled"** — host keys are
  persisted in the `sshhostkeys` volume so this shouldn't recur. If it does after
  a fresh volume, clear the stale key on your Mac:
  `ssh-keygen -R '[solstice.local]:<SSH_PORT>'`, then reconnect.
- **Dev server unreachable from Mac** — check the VS Code **Ports** panel; use
  `127.0.0.1:DEV_PORT` not `localhost`; confirm the server binds `0.0.0.0`
  (`ss -ltnp | grep DEV_PORT` should show `0.0.0.0`/`*`, not `::1`).
- **White screen via code-server proxy** — don't use the proxy for web apps; use
  the published `DEV_PORT` instead (see "Running dev servers").
- **`Blocked request … host not allowed`** — set `server.allowedHosts` in the
  app's dev-server config.
