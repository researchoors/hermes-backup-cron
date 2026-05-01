#!/usr/bin/env bash
# Hermes Backup Cron
# Pushes verbatim copy of all Hermes agent data to the private hermes-backup repo.
# No secrets embedded — reads GitHub token via `gh auth token` at runtime.
set -euo pipefail

readonly HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
readonly STATE_DB="$HERMES_HOME/state.db"
readonly REPO_URL="https://x-access-token:$(gh auth token)@github.com/researchoors/hermes-backup.git"
readonly TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

BACKUP_DIR=""
REPO_DIR=""

cleanup() {
    rm -rf "$BACKUP_DIR" "$REPO_DIR"
}
trap cleanup EXIT

# ── Prepare staging directory ──
BACKUP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/hermes-backup.XXXXXX")
REPO_DIR=$(mktemp -d "${TMPDIR:-/tmp}/hermes-backup-repo.XXXXXX")
mkdir -p "$BACKUP_DIR/memories" "$BACKUP_DIR/skills" "$BACKUP_DIR/sessions"

# ── Memories (verbatim) ──
if [[ -d "$HERMES_HOME/memories" ]]; then
    cp "$HERMES_HOME/memories/"*.md "$BACKUP_DIR/memories/" 2>/dev/null || true
fi

# ── Skills (verbatim, full tree) ──
if [[ -d "$HERMES_HOME/skills" ]]; then
    cp -R "$HERMES_HOME/skills/"* "$BACKUP_DIR/skills/" 2>/dev/null || true
fi

# ── Session states (export from state.db) ──
if [[ -f "$STATE_DB" ]]; then
    sqlite3 "$STATE_DB" "
        SELECT json_group_array(json_object(
            'id', id, 'source', source, 'model', model,
            'started_at', started_at, 'ended_at', ended_at,
            'message_count', message_count, 'tool_call_count', tool_call_count,
            'input_tokens', input_tokens, 'output_tokens', output_tokens,
            'title', title, 'estimated_cost_usd', estimated_cost_usd
        )) FROM sessions;" > "$BACKUP_DIR/sessions/index.json" 2>/dev/null || true

    while IFS= read -r sid; do
        [[ -z "$sid" ]] && continue
        local safe_name
        safe_name=$(echo "$sid" | tr '/' '_')
        sqlite3 "$STATE_DB" "
            SELECT json_group_array(json_object(
                'role', role, 'content', content,
                'tool_name', tool_name, 'timestamp', timestamp,
                'token_count', token_count
            )) FROM messages WHERE session_id='${sid}';" > "$BACKUP_DIR/sessions/${safe_name}.json" 2>/dev/null || true
    done < <(sqlite3 "$STATE_DB" "SELECT id FROM sessions ORDER BY started_at DESC;")
fi

# ── Persona, SOUL, Config ──
cp "$HERMES_HOME/persona.md" "$BACKUP_DIR/" 2>/dev/null || true
cp "$HERMES_HOME/SOUL.md" "$BACKUP_DIR/" 2>/dev/null || true
cp "$HERMES_HOME/config.yaml" "$BACKUP_DIR/" 2>/dev/null || true

echo "$TIMESTAMP" > "$BACKUP_DIR/.last-backup"

# ── Clone and sync ──
if ! git clone --depth 1 "$REPO_URL" "$REPO_DIR" 2>/dev/null; then
    git init "$REPO_DIR"
    cd "$REPO_DIR"
    git remote add origin "$REPO_URL"
fi

cd "$REPO_DIR"
rm -rf memories skills sessions persona.md SOUL.md config.yaml .last-backup
cp -R "$BACKUP_DIR/"* .

# ── Commit and push ──
git add -A
if git diff --cached --quiet; then
    echo "No changes to commit"
else
    git -c user.name="Hermes Agent" -c user.email="hermes@backup" commit -m "backup: $TIMESTAMP"
    git push origin HEAD:main 2>/dev/null || (git branch -M main && git push -u origin main)
fi

echo "Backup complete: $TIMESTAMP"
