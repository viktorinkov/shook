#!/usr/bin/env bash
# Optional: adds the [STE] badge to your Claude Code status line.
# Copies the badge script to ~/.claude/simple-english-hook/ (a stable path, independent
# of plugin versions) and adds one line to your status line script. Safe to run again.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST="$CFG/simple-english-hook"
MARK="# simple-english-hook"

mkdir -p "$DEST"
cp "$HERE/hooks/common.sh" "$HERE/hooks/statusline.sh" "$DEST/"
LINE="ste_badge=\$(printf '%s' \"\$input\" | bash \"$DEST/statusline.sh\" 2>/dev/null); [ -n \"\$ste_badge\" ] && printf '%s | ' \"\$ste_badge\"  $MARK"

cmd="$(jq -r '.statusLine.command // ""' "$CFG/settings.json" 2>/dev/null || true)"
file="$(printf '%s' "$cmd" | sed -E 's/^(bash|sh) +//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')"

if [ -z "$file" ]; then
  file="$CFG/statusline.sh"
  printf '#!/usr/bin/env bash\ninput=$(cat)\n%s\nprintf "%%s" "$(printf "%%s" "$input" | jq -r .model.display_name)"\n' "$LINE" > "$file"
  chmod +x "$file"
  tmp="$(mktemp)"; jq --arg c "bash \"$file\"" '.statusLine={type:"command",command:$c}' "$CFG/settings.json" > "$tmp" && mv "$tmp" "$CFG/settings.json"
  echo "created status line: $file"
  exit 0
fi

[ -f "$file" ] || { echo "status line script not found: $file" >&2; exit 1; }
grep -q '^input=\$(cat)' "$file" || { echo "add this line after your script reads stdin:" >&2; echo "  $LINE" >&2; exit 1; }
cp "$file" "$file.bak"
grep -v "$MARK" "$file" > "$file.tmp" || true
awk -v line="$LINE" '{print} /^input=\$\(cat\)/ && !done {print line; done=1}' "$file.tmp" > "$file" && rm "$file.tmp"
echo "badge line added to $file (backup: $file.bak)"
