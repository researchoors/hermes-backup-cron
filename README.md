# hermes-backup-cron

Cron job that pushes a verbatim backup of all Hermes agent data to the private [hermes-backup](https://github.com/researchoors/hermes-backup) repository.

## What it backs up

| Source | Destination |
|---|---|
| `~/.hermes/memories/` | `memories/` |
| `~/.hermes/skills/` | `skills/` |
| `~/.hermes/state.db` (sessions) | `sessions/index.json` + per-session `.json` |
| `~/.hermes/persona.md` | `persona.md` |
| `~/.hermes/SOUL.md` | `SOUL.md` |
| `~/.hermes/config.yaml` | `config.yaml` |

## Usage

```bash
./backup.sh
```

### Requirements

- `gh` CLI authenticated with repo access
- `git`, `sqlite3`
- `HERMES_HOME` (default: `~/.hermes`)

### Cron

Runs every hour via Hermes cron scheduler.

## Security

- No secrets are embedded in the script — reads `gh auth token` at runtime
- CI includes a check that rejects any embedded credentials
- The target repo (`hermes-backup`) is **private** — access control is the protection layer
