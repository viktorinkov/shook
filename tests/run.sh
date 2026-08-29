#!/usr/bin/env bash
# Hook tests. Each block simulates one harness: it sets the harness env vars,
# pipes sample JSON into the hooks, and checks the output format.
# Run: bash tests/run.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
H="$ROOT/hooks"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

pass=0; fail=0
check() { # check <name> <command...>   passes when the command exits 0
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL: %s\n' "$name" >&2; fi
}
has()   { printf '%s' "$1" | grep -q -- "$2"; }
lacks() { ! has "$1" "$2"; }
jqok()  { printf '%s' "$1" | jq -e "$2" >/dev/null; }

# Fake simple-english plugin: rule text plus a stub linter that counts modal verbs.
PLUG="$T/SimpleEnglish"
mkdir -p "$PLUG/output-styles" "$PLUG/evals" "$T/home" "$T/proj"
printf -- '---\nname: simple-english\n---\n\nRULE TEXT MARKER. Write short sentences.\n' > "$PLUG/output-styles/simple-english.md"
cat > "$PLUG/evals/ste_lint.py" <<'PY'
import json, re, sys
text = sys.stdin.read()
words = len(text.split())
n = len(re.findall(r"\b(should|would|could|may|might)\b", text, re.I))
print(json.dumps({"words": words, "violations_total": n,
                  "violations_per_100w": round(100.0 * n / max(words, 1), 2),
                  "longest_sentence_words": words, "violations": {"modal": n}}))
PY
PROJ="$T/proj"
BAD="You should probably refactor this. It would be nicer and it could be faster. We may also want tests, which might help. $(printf 'word %.0s' $(seq 1 40))"
GOOD="Run the tests. Then commit the change. The build takes one minute. $(printf 'word %.0s' $(seq 1 40))"

# hook <script> <stdin json> [VAR=value ...]  Runs a hook with a clean harness environment.
hook() {
  local script="$1" json="$2"; shift 2
  printf '%s' "$json" | env -u STE_MODE -u CLAUDE_PROJECT_DIR -u PLUGIN_DATA -u COPILOT_PLUGIN_DATA \
    -u GEMINI_SESSION_ID -u GEMINI_CLI_HOME -u STE_HARNESS \
    HOME="$T/home" CLAUDE_CONFIG_DIR="$T/claude" STE_PLUGIN_DIR="$PLUG" "$@" bash "$H/$script" 2>/dev/null
}
flag() { head -n1 "$1" 2>/dev/null; }

# ---- Claude Code ------------------------------------------------------------
CL=(CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_PLUGIN_ROOT="$ROOT")
out="$(hook session-start.sh '{"cwd":"'"$PROJ"'"}' STE_MODE=on "${CL[@]}")"
check "claude: session start is SessionStart JSON" jqok "$out" '.hookSpecificOutput.hookEventName == "SessionStart"'
check "claude: session start carries the rules" jqok "$out" '.hookSpecificOutput.additionalContext | test("RULE TEXT MARKER") and test("Level: on") and test("/ste off")'
check "claude: session start mentions the badge" jqok "$out" '.hookSpecificOutput.additionalContext | test("status line badge")'
out="$(hook session-start.sh '{}' "${CL[@]}")"
check "claude: silent when off" test -z "$out"
out="$(hook user-prompt-submit.sh '{"prompt":"/ste strict"}' "${CL[@]}")"
check "claude: /ste strict prints plain text" lacks "$out" '^{'
check "claude: /ste strict confirms the mode" has "$out" 'STE MODE IS NOW: strict (source: global'
check "claude: /ste strict prints the rules" has "$out" 'RULE TEXT MARKER'
check "claude: flag written to CLAUDE_CONFIG_DIR" test "$(flag "$T/claude/.simple-english-active")" = strict
out="$(hook user-prompt-submit.sh '{"prompt":"hello"}' "${CL[@]}")"
check "claude: reminder on a normal prompt" has "$out" 'STE MODE ACTIVE'
check "claude: strict line on a normal prompt" has "$out" 'STRICT:'
out="$(hook stop-gate.sh '{"last_assistant_message":"'"$BAD"'","stop_hook_active":false}' "${CL[@]}")"
check "claude: stop gate blocks a bad reply" jqok "$out" '.decision == "block" and (.reason | test("STE LINT FAILED"))'
out="$(hook stop-gate.sh '{"last_assistant_message":"'"$BAD"'","stop_hook_active":true}' "${CL[@]}")"
check "claude: stop gate runs once per turn" test -z "$out"
out="$(hook stop-gate.sh '{"last_assistant_message":"'"$GOOD"'"}' "${CL[@]}")"
check "claude: stop gate passes a good reply" test -z "$out"
out="$(hook user-prompt-submit.sh '{"prompt":"/ste project off"}' "${CL[@]}")"
check "claude: project file written" test "$(flag "$PROJ/.claude/ste-mode")" = off
check "claude: project file wins" has "$out" 'STE MODE IS NOW: off (source: project'
out="$(hook user-prompt-submit.sh '{"prompt":"/ste project clear"}' "${CL[@]}")"
check "claude: project file cleared" test ! -e "$PROJ/.claude/ste-mode"
out="$(hook user-prompt-submit.sh '{"prompt":"/ste off"}' "${CL[@]}")"
check "claude: /ste off removes the flag" test ! -e "$T/claude/.simple-english-active"
check "claude: /ste off confirms" has "$out" 'STE MODE IS NOW: off'

# ---- Codex CLI --------------------------------------------------------------
# Environment and stdin as observed in Codex CLI 0.149.0 (see docs/other-harnesses.md).
# Codex sets PLUGIN_ROOT, PLUGIN_DATA and the CLAUDE_* aliases. It does not set CLAUDE_PROJECT_DIR.
CX=(PLUGIN_DATA="$T/codex-data" CLAUDE_PLUGIN_DATA="$T/codex-data" CLAUDE_PLUGIN_ROOT="$ROOT" PLUGIN_ROOT="$ROOT")
IN='{"session_id":"01a04aca-7796-7500-bb6c-e66bbf5d49af","turn_id":"01a04aca-781c-7ee3-9cf8-810b08fc401c","transcript_path":"'"$T"'/rollout.jsonl","cwd":"'"$PROJ"'","model":"gpt-5.6-sol","permission_mode":"default"'
out="$(hook user-prompt-submit.sh "$IN"',"hook_event_name":"UserPromptSubmit","prompt":"$ste strict"}' "${CX[@]}")"
check "codex: \$ste strict is UserPromptSubmit JSON" jqok "$out" '.hookSpecificOutput.hookEventName == "UserPromptSubmit"'
check "codex: \$ste strict confirms in additionalContext" jqok "$out" '.hookSpecificOutput.additionalContext | test("STE MODE IS NOW: strict") and test("RULE TEXT MARKER")'
check "codex: systemMessage on toggle" jqok "$out" '.systemMessage == "STE mode: strict"'
check "codex: flag written to PLUGIN_DATA" test "$(flag "$T/codex-data/.simple-english-active")" = strict
check "codex: Claude flag untouched" test ! -e "$T/claude/.simple-english-active"
# The skill picker inserts "$simple-english-hook:ste " (with a trailing space) in front of the arguments.
out="$(hook user-prompt-submit.sh "$IN"',"hook_event_name":"UserPromptSubmit","prompt":"$simple-english-hook:ste  status"}' "${CX[@]}")"
check "codex: picker mention reaches the hook as text" jqok "$out" '.hookSpecificOutput.additionalContext | test("STE MODE IS NOW: strict \\(source: global")'
check "codex: status keeps the flag" test "$(flag "$T/codex-data/.simple-english-active")" = strict
out="$(hook session-start.sh "$IN"',"hook_event_name":"SessionStart","source":"startup"}' "${CX[@]}")"
check "codex: session start JSON" jqok "$out" '.hookSpecificOutput.hookEventName == "SessionStart" and .systemMessage == "STE mode: strict"'
check "codex: session start names \$ste" jqok "$out" '.hookSpecificOutput.additionalContext | test("\\$ste off") and (test("status line badge") | not)'
out="$(hook user-prompt-submit.sh "$IN"',"hook_event_name":"UserPromptSubmit","prompt":"hello"}' "${CX[@]}")"
check "codex: reminder is JSON without systemMessage" jqok "$out" '(.hookSpecificOutput.additionalContext | test("STE MODE ACTIVE")) and (has("systemMessage") | not)'
out="$(hook stop-gate.sh "$IN"',"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"'"$BAD"'"}' "${CX[@]}")"
check "codex: stop gate blocks" jqok "$out" '.decision == "block"'
check "codex: score written to PLUGIN_DATA" test -s "$T/codex-data/.simple-english-score"
out="$(hook stop-gate.sh "$IN"',"hook_event_name":"Stop","stop_hook_active":true,"last_assistant_message":"'"$BAD"'"}' "${CX[@]}")"
check "codex: stop gate runs once per turn" test -z "$out"
mkdir -p "$PROJ/.claude"; printf 'off\n' > "$PROJ/.claude/ste-mode"
out="$(hook user-prompt-submit.sh "$IN"',"hook_event_name":"UserPromptSubmit","prompt":"hello"}' "${CX[@]}")"
check "codex: project file found through cwd" test -z "$out"
rm -f "$PROJ/.claude/ste-mode"
out="$(hook user-prompt-submit.sh "$IN"',"hook_event_name":"UserPromptSubmit","prompt":"$ste off"}' "${CX[@]}")"
check "codex: \$ste off removes the flag" test ! -e "$T/codex-data/.simple-english-active"

# ---- GitHub Copilot CLI -----------------------------------------------------
CP=(COPILOT_PLUGIN_DATA="$T/copilot-data" PLUGIN_DATA="$T/codex-shadow" PLUGIN_ROOT="$ROOT")
IN='{"cwd":"'"$PROJ"'","sessionId":"s1"'
out="$(hook user-prompt-submit.sh "$IN"',"prompt":"/simple-english-hook:ste strict"}' "${CP[@]}")"
check "copilot: prompt hook prints nothing" test -z "$out"
check "copilot: flag written to COPILOT_PLUGIN_DATA" test "$(flag "$T/copilot-data/.simple-english-active")" = strict
check "copilot: Codex PLUGIN_DATA untouched" test ! -e "$T/codex-shadow/.simple-english-active"
out="$(hook session-start.sh "$IN"',"source":"startup"}' "${CP[@]}")"
check "copilot: session start is {additionalContext}" jqok "$out" '(.additionalContext | test("RULE TEXT MARKER")) and (has("hookSpecificOutput") | not)'
check "copilot: strict downgrades to on" jqok "$out" '.additionalContext | test("Level: on") and test("/simple-english-hook:ste off")'
out="$(hook stop-gate.sh "$IN"',"stopReason":"end_turn","stop_hook_active":false}' "${CP[@]}")"
check "copilot: stop gate is a no-op" test -z "$out"
hook user-prompt-submit.sh "$IN"',"prompt":"/simple-english-hook:ste off"}' "${CP[@]}" >/dev/null
check "copilot: off removes the flag" test ! -e "$T/copilot-data/.simple-english-active"

# ---- Gemini CLI -------------------------------------------------------------
GM=(GEMINI_SESSION_ID=s1 GEMINI_CWD="$PROJ" GEMINI_PROJECT_DIR="$PROJ" CLAUDE_PROJECT_DIR="$PROJ" GEMINI_CLI_HOME="$T/gemhome")
IN='{"cwd":"'"$PROJ"'","session_id":"s1"'
out="$(hook user-prompt-submit.sh "$IN"',"hook_event_name":"BeforeAgent","prompt":"/ste strict"}' "${GM[@]}")"
check "gemini: /ste strict is BeforeAgent JSON" jqok "$out" '.hookSpecificOutput.hookEventName == "BeforeAgent" and .systemMessage == "STE mode: strict"'
check "gemini: flag written under GEMINI_CLI_HOME/.gemini" test "$(flag "$T/gemhome/.gemini/.simple-english-active")" = strict
out="$(hook session-start.sh "$IN"',"source":"startup"}' "${GM[@]}")"
check "gemini: session start JSON" jqok "$out" '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | test("RULE TEXT MARKER"))'
out="$(hook user-prompt-submit.sh "$IN"',"prompt":"hello"}' "${GM[@]}")"
check "gemini: reminder is BeforeAgent JSON" jqok "$out" '.hookSpecificOutput.hookEventName == "BeforeAgent" and (.hookSpecificOutput.additionalContext | test("STE MODE ACTIVE"))'
out="$(hook stop-gate.sh "$IN"',"prompt":"hi","prompt_response":"'"$BAD"'","stop_hook_active":false}' "${GM[@]}")"
check "gemini: AfterAgent blocks a bad reply" jqok "$out" '.decision == "block"'
out="$(hook stop-gate.sh "$IN"',"prompt":"hi","prompt_response":"'"$BAD"'","stop_hook_active":true}' "${GM[@]}")"
check "gemini: AfterAgent runs once per turn" test -z "$out"
hook user-prompt-submit.sh "$IN"',"prompt":"/ste off"}' "${GM[@]}" >/dev/null
check "gemini: /ste off removes the flag" test ! -e "$T/gemhome/.gemini/.simple-english-active"

# ---- Overrides and missing plugin -------------------------------------------
out="$(hook session-start.sh '{}' STE_MODE=on STE_HARNESS=codex CLAUDE_PROJECT_DIR="$PROJ")"
check "STE_HARNESS override selects the Codex format" jqok "$out" '.systemMessage == "STE mode: on"'
out="$(hook session-start.sh '{}' STE_MODE=on STE_PLUGIN_DIR="$T/nowhere" CLAUDE_PROJECT_DIR="$PROJ")"
check "missing plugin: note names STE_PLUGIN_DIR" jqok "$out" '.hookSpecificOutput.additionalContext | test("STE_PLUGIN_DIR")'

# ---- Manifests --------------------------------------------------------------
for f in hooks/hooks.json hooks/copilot-hooks.json gemini/hooks/hooks.json .claude-plugin/plugin.json \
         .claude-plugin/marketplace.json .codex-plugin/plugin.json .agents/plugins/marketplace.json \
         .github/plugin/plugin.json .github/plugin/marketplace.json gemini/gemini-extension.json; do
  check "valid JSON: $f" jq -e . "$ROOT/$f"
done
check "claude hooks.json keeps its three events" jq -e '.hooks | keys == ["SessionStart","Stop","UserPromptSubmit"]' "$ROOT/hooks/hooks.json"
check "codex manifest reuses hooks/hooks.json and skills" jq -e '.hooks == "./hooks/hooks.json" and .skills == "./skills/"' "$ROOT/.codex-plugin/plugin.json"
check "copilot hooks use the native format" jq -e '.version == 1 and (.hooks | keys == ["sessionStart","userPromptSubmitted"]) and (.hooks.sessionStart[0].bash | test("PLUGIN_ROOT"))' "$ROOT/hooks/copilot-hooks.json"
check "copilot manifest points at copilot-hooks.json" jq -e '.hooks == "hooks/copilot-hooks.json" and .skills == "skills/"' "$ROOT/.github/plugin/plugin.json"
check "gemini hooks use Gemini events only" jq -e '.hooks | keys == ["AfterAgent","BeforeAgent","SessionStart"]' "$ROOT/gemini/hooks/hooks.json"
check "gemini hooks point at the shared scripts" jq -e '[.hooks[][].hooks[].command] | all(test("extensionPath\\}/\\.\\./hooks/"))' "$ROOT/gemini/hooks/hooks.json"
check "gemini extension exposes the ste skill" test -f "$ROOT/gemini/skills/ste/SKILL.md"
check "gemini /ste command forwards its arguments" grep -q '^prompt = "/ste {{args}}"' "$ROOT/gemini/commands/ste.toml"
v="$(jq -r .version "$ROOT/.claude-plugin/plugin.json")"
for f in .codex-plugin/plugin.json .github/plugin/plugin.json gemini/gemini-extension.json; do
  check "version $v in $f" test "$(jq -r .version "$ROOT/$f")" = "$v"
done

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
