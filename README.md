# EnvSync CLI

`envsync` syncs project secrets from EnvSync backend into your local `.env`.
For project admins, `sync` also publishes changed values from local `.env` back to the backend before pulling.
It supports backend version-aware sync (`client_version`/`server_version`) and rotated key updates.

---

## Quick Start

### 1. Install dependencies

```bash
mix deps.get
```

### 2. Build the CLI binary

```bash
mix escript.build
```

This generates `./envsync`.

### 3. Install globally (optional)

```bash
sudo cp ./envsync /usr/local/bin/envsync
```

---

## Configuration

The CLI reads these environment variables:

- `ENVSYNC_BACKEND_URL` (default: `http://localhost:4000`)
- `ENVSYNC_CALLBACK_PORT` (default: `9292`)
- `ENVSYNC_SYNC_INTERVAL` (default: `30`, used by `watch`)
- `ENVSYNC_STATE_DIR` (default: `~/.config/envsync`, stores project sync versions)

---

## Authentication

Run:

```bash
envsync auth login
```

Logout:

```bash
envsync auth logout
```

Logout clears both auth token and local project sync version state.

---

## Commands

| Command | Description |
|---|---|
| `envsync auth login` | Authenticate with GitHub |
| `envsync auth logout` | Clear local session token + sync state |
| `envsync whoami` | Show authenticated identity |
| `envsync projects` | List accessible projects |
| `envsync projects create --name <name> --repo <owner/repo> [--description <text>]` | Create project and bind verified GitHub repo |
| `envsync projects reverify --project <name>` | Re-verify project repo binding (admin) |
| `envsync check` | Compare `.env.example` vs `.env` |
| `envsync sync --project <name>` | Publish local `.env` changes if admin, then sync from backend |
| `envsync watch --project <name> [--interval N]` | Poll backend and auto-sync repeatedly |
| `envsync admin members list --project <name>` | List project members (admin) |
| `envsync admin members add --project <name> --github-login <login> [--role member\|admin]` | Assign member (admin) |
| `envsync admin members role --project <name> --member-id <id> --role <member\|admin>` | Update member role (admin) |
| `envsync admin members remove --project <name> --member-id <id>` | Remove member (admin) |
| `envsync admin sync-status --project <name>` | Show member freshness/staleness (admin) |
| `envsync admin secrets set --project <name> --key <KEY> --value <VALUE> [--description <text>]` | Create/rotate secret (admin) |
| `envsync admin secrets delete --project <name> --key <KEY>` | Delete secret (admin) |
| `envsync help` | Show command help |

---

## Common Usage

Sync once:

```bash
envsync sync --project my_app
```

Project onboarding:

```bash
envsync projects create --name my_app --repo myorg/my_app
envsync projects reverify --project my_app
```

Project create/reverify is strictly verified by backend GitHub API checks.
Backend must run with `ENVSYNC_GITHUB_VERIFY_TOKEN` configured.
Accepted repo formats: `owner/repo`, `https://github.com/owner/repo(.git)`, `git@github.com:owner/repo.git`.

Admin workflow (bulk publish):

1. Update project values in your local `.env` (keys should exist in `.env.example`).
2. Run `envsync sync --project my_app`.
3. CLI pushes changed keys to backend, then performs normal pull sync.

Watch continuously:

```bash
envsync watch --project my_app --interval 20
```

List members:

```bash
envsync admin members list --project my_app
```

Set a secret:

```bash
envsync admin secrets set --project my_app --key API_KEY --value secret123
```

---

## Developer Commands

```bash
make help
make build
make test
make install
make dist
```
