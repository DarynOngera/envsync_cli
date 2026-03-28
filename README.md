# EnvSync CLI

`envsync` is a terminal tool for syncing missing environment secrets from the EnvSync backend into your local `.env`.

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

---

## Authentication

Run:

```bash
envsync auth login
```

This opens a browser for GitHub OAuth and stores your JWT locally (keychain-first, file fallback).

Logout:

```bash
envsync auth logout
```

---

## Commands

| Command | Description |
|---|---|
| `envsync auth login` | Authenticate with GitHub |
| `envsync auth logout` | Clear local session token |
| `envsync whoami` | Show authenticated identity |
| `envsync projects` | List accessible projects |
| `envsync check` | Compare `.env.example` vs `.env` |
| `envsync sync --project <name>` | Fetch and write missing secrets |
| `envsync help` | Show command help |

---

## Common Usage

Check missing keys:

```bash
envsync check
```

Sync missing keys:

```bash
envsync sync --project my_app
```

Custom file paths:

```bash
envsync check --template .env.example --env .env.local
envsync sync --project my_app --template .env.example --env .env.local
```

---

## Developer Commands

Use the provided Makefile:

```bash
make help
make build
make test
make install
make dist
```
