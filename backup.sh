#!/usr/bin/env bash
# Hermes Backup Cron
# Pushes verbatim copy of all Hermes agent data to the private hermes-backup repo.
# No secrets embedded — reads GitHub token via `gh auth token` at runtime.
# Compresses state.db with gzip to stay under GitHub's 100MB file limit.
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
STATE_DB="$HERMES_HOME/state.db"
REPO_URL="https://x-access-token:$(gh auth token)@github.com/researchoors/hermes-backup.git"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

BACKUP_DIR=""
REPO_DIR=""

cleanup() {
    rm -rf "$BACKUP_DIR" "$REPO_DIR"
}
trap cleanup EXIT

# ── Prepare staging directory ──
BACKUP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/hermes-backup.XXXXXX")
REPO_DIR=$(mktemp -d "${TMPDIR:-/tmp}/hermes-backup-repo.XXXXXX")
mkdir -p "$BACKUP_DIR/memories" "$BACKUP_DIR/skills"

# ── Memories (verbatim) ──
if [[ -d "$HERMES_HOME/memories" ]]; then
    # shellcheck disable=SC2035
    cp "$HERMES_HOME/memories/"*.md "$BACKUP_DIR/memories/" 2>/dev/null || true
fi

# ── Skills (verbatim, full tree) ──
if [[ -d "$HERMES_HOME/skills" ]]; then
    cp -R "$HERMES_HOME/skills/"* "$BACKUP_DIR/skills/" 2>/dev/null || true
fi

# ── State DB (consistent snapshot via sqlite3 backup API, then gzip) ──
if [[ -f "$STATE_DB" ]]; then
    sqlite3 "$STATE_DB" ".backup '$BACKUP_DIR/state.db'" 2>/dev/null || cp "$STATE_DB" "$BACKUP_DIR/state.db"
    gzip -9 "$BACKUP_DIR/state.db"
fi

# ── Persona, SOUL, Config ──
cp "$HERMES_HOME/persona.md" "$BACKUP_DIR/" 2>/dev/null || true
cp "$HERMES_HOME/SOUL.md" "$BACKUP_DIR/" 2>/dev/null || true
cp "$HERMES_HOME/config.yaml" "$BACKUP_DIR/" 2>/dev/null || true

echo "$TIMESTAMP" >"$BACKUP_DIR/.last-backup"

# ── Clone and sync ──
if ! git clone --depth 1 "$REPO_URL" "$REPO_DIR" 2>/dev/null; then
    git init "$REPO_DIR"
    cd "$REPO_DIR"
    git remote add origin "$REPO_URL"
fi

cd "$REPO_DIR"

# ── Remove old LFS config if present ──
rm -f .gitattributes

# ── Sync files ──
rm -rf memories skills state.db state.db.gz persona.md SOUL.md config.yaml .last-backup sessions
cp -R "$BACKUP_DIR/"* .

# ── Commit and push ──
git add -A
if git diff --cached --quiet; then
    echo "No changes to commit"
else
    git -c user.name="hankbobtheresearchoor" -c user.email="hankbobtheresearchoor@gmail.com" commit -m "backup: $TIMESTAMP"
    git push origin HEAD:main 2>/dev/null || (git branch -M main && git push -u origin main)
fi

echo "Backup complete: $TIMESTAMP"
