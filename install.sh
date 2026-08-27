#!/usr/bin/env bash
# Installs the Simple English hook set into ~/.claude (or $CLAUDE_CONFIG_DIR).
# Safe to run more than once. Makes a backup of settings.json first.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CFG/settings.json"
MARK="simple-english-hook"   # every command we add contains this path segment

command -v jq >/dev/null || { echo "install: jq is required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "install: python3 is required" >&2; exit 1; }

# 1. Hook entries. Each has a key so a re-run replaces, not duplicates.
hook_entry() {
  jq -n --arg cmd "bash \"$HERE/hooks/$1\"" --arg msg "$2" \
    '{hooks:[{type:"command",command:$cmd,timeout:15,statusMessage:$msg}]}'
}
SS="$(hook_entry session-start.sh 'Loading Simple English rules...')"
UPS="$(hook_entry user-prompt-submit.sh 'Simple English check...')"
STOP="$(hook_entry stop-gate.sh 'Simple English lint...')"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"

tmp="$(mktemp)"
jq --arg here "$HERE" --argjson ss "$SS" --argjson ups "$UPS" --argjson stop "$STOP" '
  def drop_ours: map(select((.hooks // []) | any(.command | contains($here)) | not));
  .hooks //= {}
  | .hooks.SessionStart     = ((.hooks.SessionStart     // []) | drop_ours) + [$ss + {matcher:"startup|resume|clear|compact"}]
  | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | drop_ours) + [$ups]
  | .hooks.Stop             = ((.hooks.Stop             // []) | drop_ours) + [$stop]
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
echo "install: hooks registered in $SETTINGS"

# 2. The /ste command.
mkdir -p "$CFG/skills"
ln -sfn "$HERE/skills/ste" "$CFG/skills/ste"
echo "install: /ste command linked at $CFG/skills/ste"

# 3. Status line badge.
#    If a status line script exists, add one line that prints the badge.
#    If none exists, create a small one.
BADGE_LINE="ste_badge=\$(printf '%s' \"\$input\" | bash \"$HERE/hooks/statusline.sh\" 2>/dev/null); [ -n \"\$ste_badge\" ] && printf '%s | ' \"\$ste_badge\"  # $MARK"
sl_cmd="$(jq -r '.statusLine.command // ""' "$SETTINGS")"
sl_file="$(printf '%s' "$sl_cmd" | sed -E 's/^(bash|sh) +//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')"
if [ -n "$sl_file" ] && [ -f "$sl_file" ]; then
  if grep -q "$MARK" "$sl_file"; then
    echo "install: status line badge already present in $sl_file"
  elif grep -q '^input=\$(cat)' "$sl_file"; then
    cp "$sl_file" "$sl_file.bak.$(date +%Y%m%d%H%M%S)"
    python3 - "$sl_file" "$BADGE_LINE" <<'PY'
import sys
path, line = sys.argv[1], sys.argv[2]
src = open(path).read().split("\n")
for i, l in enumerate(src):
    if l.startswith("input=$(cat)"):
        src.insert(i + 1, line); break
open(path, "w").write("\n".join(src))
PY
    echo "install: status line badge added to $sl_file"
  else
    echo "install: could not patch $sl_file (no 'input=\$(cat)' line). Add this line after the script reads stdin:" >&2
    echo "  $BADGE_LINE" >&2
  fi
else
  sl_new="$CFG/simple-english-statusline.sh"
  printf '#!/usr/bin/env bash\ninput=$(cat)\n%s\nprintf "%%s" "$(printf "%%s" "$input" | jq -r .model.display_name)"\n' "$BADGE_LINE" > "$sl_new"
  chmod +x "$sl_new"
  tmp="$(mktemp)"; jq --arg c "bash \"$sl_new\"" '.statusLine={type:"command",command:$c}' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "install: created status line at $sl_new"
fi

# 4. Default mode for first run.
if [ ! -f "$CFG/.simple-english-active" ]; then
  printf 'on\n' > "$CFG/.simple-english-active"
  echo "install: mode set to 'on' (use /ste strict for the lint gate, /ste off to disable)"
fi

echo "install: done. Start a new Claude Code session, then check /hooks and the [STE] badge."
