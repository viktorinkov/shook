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
    -u ANTIGRAVITY_CONVERSATION_ID -u STE_HARNESS \
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

# ---- Antigravity CLI --------------------------------------------------------
# agy (1.1.22) sends no prompt and no reply text. Both come from the transcript file.
# The hook cwd is the installed plugin copy, and the root hooks.json sets STE_HARNESS.
AG=(ANTIGRAVITY_CONVERSATION_ID=c1 STE_HARNESS=antigravity HOME="$T/aghome")
TP="$T/transcript.jsonl"; : > "$TP"
IN='{"conversationId":"c1","modelName":"m","transcriptPath":"'"$TP"'"'
tstep() { # tstep <index> <source> <type> <content>   appends one transcript step
  jq -nc --argjson i "$1" --arg s "$2" --arg t "$3" --arg c "$4" '{step_index:$i,source:$s,type:$t,content:$c}' >> "$TP"
}
tuser() { tstep "$1" USER_EXPLICIT USER_INPUT "$(printf '<USER_REQUEST>\n%s\n</USER_REQUEST>\n<ADDITIONAL_METADATA>\nx\n</ADDITIONAL_METADATA>' "$2")"; }
tuser 0 "/ste strict"
out="$(hook user-prompt-submit.sh "$IN"',"workspacePaths":[],"invocationNum":0}' "${AG[@]}")"
check "antigravity: /ste strict injects an ephemeral message" jqok "$out" '.injectSteps[0].ephemeralMessage | test("STE MODE IS NOW: strict") and test("RULE TEXT MARKER") and test("project file: none")'
check "antigravity: flag written under ~/.gemini/config" test "$(flag "$T/aghome/.gemini/config/.simple-english-active")" = strict
check "antigravity: Claude flag untouched" test ! -e "$T/claude/.simple-english-active"
out="$(hook session-start.sh "$IN"',"workspacePaths":[]}' "${AG[@]}")"
check "antigravity: session start injects a system message" jqok "$out" '.injectSteps[0].systemMessage.systemMessage | test("RULE TEXT MARKER") and test("Level: strict") and test("/ste off") and (test("status line badge") | not)'
tstep 1 MODEL PLANNER_RESPONSE "STE mode is strict."
out="$(hook user-prompt-submit.sh "$IN"',"workspacePaths":[],"invocationNum":1}' "${AG[@]}")"
check "antigravity: later model calls get the reminder only" jqok "$out" '.injectSteps[0].ephemeralMessage | test("STE MODE ACTIVE") and test("STRICT:") and (test("STE MODE IS NOW") | not)'
tuser 2 "hello"; tstep 3 MODEL PLANNER_RESPONSE "$BAD"
out="$(hook stop-gate.sh "$IN"',"workspacePaths":[],"executionNum":0,"terminationReason":"NO_TOOL_CALL","fullyIdle":true}' "${AG[@]}")"
check "antigravity: stop gate continues on a bad reply" jqok "$out" '.decision == "continue" and (.reason | test("STE LINT FAILED"))'
check "antigravity: score written next to the flag" test -s "$T/aghome/.gemini/config/.simple-english-score"
tstep 4 SYSTEM SYSTEM_MESSAGE "Stop hook blocked termination: STE LINT FAILED (x)"; tstep 5 MODEL PLANNER_RESPONSE "$BAD"
out="$(hook stop-gate.sh "$IN"',"workspacePaths":[],"executionNum":1}' "${AG[@]}")"
check "antigravity: stop gate runs once per turn" test -z "$out"
tuser 6 "again"; tstep 7 MODEL PLANNER_RESPONSE "$GOOD"
out="$(hook stop-gate.sh "$IN"',"workspacePaths":[],"executionNum":0}' "${AG[@]}")"
check "antigravity: stop gate passes a good reply" test -z "$out"
mkdir -p "$T/agplugin/.claude"; printf 'off\n' > "$T/agplugin/.claude/ste-mode"
out="$(cd "$T/agplugin" && hook session-start.sh "$IN"',"workspacePaths":[]}' "${AG[@]}")"
check "antigravity: .claude/ste-mode in the plugin copy is ignored" jqok "$out" '.injectSteps[0].systemMessage.systemMessage | test("Level: strict")'
mkdir -p "$PROJ/.claude"; printf 'off\n' > "$PROJ/.claude/ste-mode"
out="$(hook session-start.sh "$IN"',"workspacePaths":["'"$PROJ"'"]}' "${AG[@]}")"
check "antigravity: project file found through workspacePaths" test -z "$out"
rm -f "$PROJ/.claude/ste-mode"
out="$(hook user-prompt-submit.sh "$IN"',"workspacePaths":[]}' ANTIGRAVITY_CONVERSATION_ID=c1 HOME="$T/aghome")"
check "antigravity: detected from ANTIGRAVITY_CONVERSATION_ID alone" jqok "$out" '.injectSteps[0].ephemeralMessage | test("STE MODE ACTIVE")'
tuser 8 "/ste off"
hook user-prompt-submit.sh "$IN"',"workspacePaths":[]}' "${AG[@]}" >/dev/null
check "antigravity: /ste off removes the flag" test ! -e "$T/aghome/.gemini/config/.simple-english-active"

# ---- Overrides and missing plugin -------------------------------------------
out="$(hook session-start.sh '{}' STE_MODE=on STE_HARNESS=codex CLAUDE_PROJECT_DIR="$PROJ")"
check "STE_HARNESS override selects the Codex format" jqok "$out" '.systemMessage == "STE mode: on"'
out="$(hook session-start.sh '{}' STE_MODE=on STE_PLUGIN_DIR="$T/nowhere" CLAUDE_PROJECT_DIR="$PROJ")"
check "missing plugin: note names STE_PLUGIN_DIR" jqok "$out" '.hookSpecificOutput.additionalContext | test("STE_PLUGIN_DIR")'

# ---- Manifests --------------------------------------------------------------
for f in hooks/hooks.json hooks/copilot-hooks.json hooks.json plugin.json .claude-plugin/plugin.json \
         .claude-plugin/marketplace.json .codex-plugin/plugin.json .agents/plugins/marketplace.json \
         .github/plugin/plugin.json .github/plugin/marketplace.json; do
  check "valid JSON: $f" jq -e . "$ROOT/$f"
done
check "claude hooks.json keeps its three events" jq -e '.hooks | keys == ["SessionStart","Stop","UserPromptSubmit"]' "$ROOT/hooks/hooks.json"
check "codex manifest reuses hooks/hooks.json and skills" jq -e '.hooks == "./hooks/hooks.json" and .skills == "./skills/"' "$ROOT/.codex-plugin/plugin.json"
check "copilot hooks use the native format" jq -e '.version == 1 and (.hooks | keys == ["sessionStart","userPromptSubmitted"]) and (.hooks.sessionStart[0].bash | test("PLUGIN_ROOT"))' "$ROOT/hooks/copilot-hooks.json"
check "copilot manifest points at copilot-hooks.json" jq -e '.hooks == "hooks/copilot-hooks.json" and .skills == "skills/"' "$ROOT/.github/plugin/plugin.json"
check "antigravity hooks.json is one named hook with agy events" jq -e 'keys == ["simple-english-hook"] and (.["simple-english-hook"] | keys == ["PreInvocation","SessionStart","Stop"])' "$ROOT/hooks.json"
check "antigravity hooks use relative paths and set the harness" jq -e '[.["simple-english-hook"][][] | .command] | length == 3 and all(test("^STE_HARNESS=antigravity bash hooks/[a-z-]+\\.sh$"))' "$ROOT/hooks.json"
check "antigravity plugin.json has name and description only" jq -e '.name == "simple-english-hook" and keys == ["description","name"]' "$ROOT/plugin.json"
check "gemini directory removed" test ! -e "$ROOT/gemini"
v="$(jq -r .version "$ROOT/.claude-plugin/plugin.json")"
for f in .codex-plugin/plugin.json .github/plugin/plugin.json; do
  check "version $v in $f" test "$(jq -r .version "$ROOT/$f")" = "$v"
done

# ---- Settings: /ste config, /ste set, /ste unset ----------------------------
# The config file and the gate settings. See the settings block in hooks/common.sh.
unset STE_MIN_WORDS STE_MIN_TOTAL STE_MAX_PER_100W STE_LINT_TYPE 2>/dev/null || true
hasE() { printf '%s' "$1" | grep -Eq -- "$2"; }
CFG_G="$T/claude/simple-english-hook.json"
CFG_P="$PROJ/.claude/ste-config.json"

out="$(hook user-prompt-submit.sh '{"prompt":"/ste config"}' "${CL[@]}")"
check "config: prints plain text" lacks "$out" '^{'
check "config: header names mode and source" has "$out" 'STE CONFIG (mode: off, source: default):'
check "config: min-words default row" hasE "$out" 'min-words +40 +default +STE_MIN_WORDS'
check "config: min-total default row" hasE "$out" 'min-total +2 +default +STE_MIN_TOTAL'
check "config: max-per-100w default row" hasE "$out" 'max-per-100w +1.0 +default +STE_MAX_PER_100W'
check "config: lint-type default row" hasE "$out" 'lint-type +descriptive +default +STE_LINT_TYPE'
check "config: names both files" has "$out" 'project file:'
check "config: reply instruction" has "$out" 'Reply with the STE CONFIG table above'

out="$(hook user-prompt-submit.sh '{"prompt":"/ste set min-words 10"}' "${CL[@]}")"
check "set: confirms key, value and file" has "$out" "STE SETTING SAVED: min-words = 10 (global file: $CFG_G)"
check "set: writes the global file" jq -e '.min_words == 10' "$CFG_G"
check "set: table shows the global source" hasE "$out" 'min-words +10 +global'

out="$(hook user-prompt-submit.sh '{"prompt":"/ste project set max-per-100w 50"}' "${CL[@]}")"
check "project set: writes the project file" jq -e '.max_per_100w == 50' "$CFG_P"
check "project set: table shows the project source" hasE "$out" 'max-per-100w +50 +project'

hook user-prompt-submit.sh '{"prompt":"/ste project set min-words 20"}' "${CL[@]}" >/dev/null
out="$(hook user-prompt-submit.sh '{"prompt":"/ste config"}' STE_MIN_WORDS=30 "${CL[@]}")"
check "precedence: env beats project" hasE "$out" 'min-words +30 +env'
out="$(hook user-prompt-submit.sh '{"prompt":"/ste config"}' "${CL[@]}")"
check "precedence: project beats global" hasE "$out" 'min-words +20 +project'
out="$(hook user-prompt-submit.sh '{"prompt":"/ste project unset min-words"}' "${CL[@]}")"
check "project unset: confirms" has "$out" 'STE SETTING REMOVED: min-words (project file:'
check "precedence: global after project unset" hasE "$out" 'min-words +10 +global'
out="$(hook user-prompt-submit.sh '{"prompt":"/ste unset min-words"}' "${CL[@]}")"
check "unset: removes the key" jq -e 'has("min_words") | not' "$CFG_G"
check "precedence: default after unset" hasE "$out" 'min-words +40 +default'

out="$(hook user-prompt-submit.sh '{"prompt":"/ste set min-words abc"}' "${CL[@]}")"
check "validation: min-words abc rejected" has "$out" 'STE: invalid value "abc" for min-words'
out="$(hook user-prompt-submit.sh '{"prompt":"/ste set max-per-100w -1"}' "${CL[@]}")"
check "validation: max-per-100w -1 rejected" has "$out" 'STE: invalid value "-1" for max-per-100w'
out="$(hook user-prompt-submit.sh '{"prompt":"/ste set lint-type foo"}' "${CL[@]}")"
check "validation: lint-type foo rejected" has "$out" 'STE: invalid value "foo" for lint-type'
check "validation: usage message is present" has "$out" 'usage:'
out="$(hook user-prompt-submit.sh '{"prompt":"/ste set bogus 1"}' "${CL[@]}")"
check "validation: unknown key rejected" has "$out" 'STE: unknown key "bogus"'
check "validation: nothing invalid written" jq -e '(has("min_words") or has("lint_type") or has("bogus")) | not' "$CFG_G"

out="$(hook user-prompt-submit.sh '{"prompt":"/ste project set lint-type procedural"}' "${CL[@]}")"
check "lint-type: procedural accepted" hasE "$out" 'lint-type +procedural +project'
hook user-prompt-submit.sh '{"prompt":"/ste project unset lint-type"}' "${CL[@]}" >/dev/null
hook user-prompt-submit.sh '{"prompt":"/ste project unset max-per-100w"}' "${CL[@]}" >/dev/null

# The gate reads the settings. A project min_words of 10 blocks a 20-word slop reply.
hook user-prompt-submit.sh '{"prompt":"/ste strict"}' "${CL[@]}" >/dev/null
hook user-prompt-submit.sh '{"prompt":"/ste project set min-words 10"}' "${CL[@]}" >/dev/null
SHORTBAD="You should refactor this right now because it would be nicer and it could go faster and it may break."
out="$(hook stop-gate.sh '{"last_assistant_message":"'"$SHORTBAD"'","stop_hook_active":false}' "${CL[@]}")"
check "gate: project min-words 10 blocks a short slop reply" jqok "$out" '.decision == "block"'
hook user-prompt-submit.sh '{"prompt":"/ste project unset min-words"}' "${CL[@]}" >/dev/null
out="$(hook stop-gate.sh '{"last_assistant_message":"'"$SHORTBAD"'","stop_hook_active":false}' "${CL[@]}")"
check "gate: default min-words passes the same reply" test -z "$out"
# A global max_per_100w of 50 lets a bad reply through.
hook user-prompt-submit.sh '{"prompt":"/ste set max-per-100w 50"}' "${CL[@]}" >/dev/null
out="$(hook stop-gate.sh '{"last_assistant_message":"'"$BAD"'","stop_hook_active":false}' "${CL[@]}")"
check "gate: global max-per-100w 50 passes a bad reply" test -z "$out"
hook user-prompt-submit.sh '{"prompt":"/ste unset max-per-100w"}' "${CL[@]}" >/dev/null
out="$(hook stop-gate.sh '{"last_assistant_message":"'"$BAD"'","stop_hook_active":false}' "${CL[@]}")"
check "gate: defaults block the bad reply again" jqok "$out" '.decision == "block"'
hook user-prompt-submit.sh '{"prompt":"/ste off"}' "${CL[@]}" >/dev/null

# Codex and Antigravity keep the config file in their own state directories.
out="$(hook user-prompt-submit.sh '{"cwd":"'"$PROJ"'","hook_event_name":"UserPromptSubmit","prompt":"$ste set min-total 3"}' "${CX[@]}")"
check "codex: \$ste set confirms in additionalContext" jqok "$out" '.hookSpecificOutput.additionalContext | test("STE SETTING SAVED: min-total = 3")'
check "codex: config written to PLUGIN_DATA" jq -e '.min_total == 3' "$T/codex-data/simple-english-hook.json"
rm -f "$T/codex-data/simple-english-hook.json"
TP2="$T/transcript-settings.jsonl"; : > "$TP2"
jq -nc --arg c "$(printf '<USER_REQUEST>\n/ste set min-total 3\n</USER_REQUEST>')" \
  '{step_index:0,source:"USER_EXPLICIT",type:"USER_INPUT",content:$c}' >> "$TP2"
out="$(hook user-prompt-submit.sh '{"conversationId":"c9","transcriptPath":"'"$TP2"'","workspacePaths":[],"invocationNum":0}' "${AG[@]}")"
check "antigravity: /ste set works from the transcript" jqok "$out" '.injectSteps[0].ephemeralMessage | test("STE SETTING SAVED: min-total = 3")'
check "antigravity: config under ~/.gemini/config" jq -e '.min_total == 3' "$T/aghome/.gemini/config/simple-english-hook.json"

# ---- /ste uninstall ---------------------------------------------------------
U="$T/uclaude"; UP="$T/uproj"; UCL=(CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_CONFIG_DIR="$U" CLAUDE_PROJECT_DIR="$UP")
mkdir -p "$U/simple-english-hook" "$UP/.claude"
printf '#!/usr/bin/env bash\ninput=$(cat)\nste_badge=x  # simple-english-hook\necho custom-line\n' > "$U/sl.sh"
cp "$U/sl.sh" "$U/sl.sh.bak"
jq -n --arg c "bash \"$U/sl.sh\"" '{statusLine:{type:"command",command:$c},other:1}' > "$U/settings.json"
printf 'strict\n' > "$U/.simple-english-active"
printf '0.0 0 10\n' > "$U/.simple-english-score"
printf '{"min_words":10}\n' > "$U/simple-english-hook.json"
printf 'on\n' > "$UP/.claude/ste-mode"
printf '{"min_total":3}\n' > "$UP/.claude/ste-config.json"
out="$(hook user-prompt-submit.sh '{"prompt":"/ste uninstall"}' "${UCL[@]}")"
check "uninstall: badge line removed" lacks "$(cat "$U/sl.sh")" 'simple-english-hook'
check "uninstall: other statusline lines survive" has "$(cat "$U/sl.sh")" 'custom-line'
check "uninstall: statusline backup deleted" test ! -e "$U/sl.sh.bak"
check "uninstall: settings.json untouched for a user script" jq -e '.statusLine.command != null and .other == 1' "$U/settings.json"
check "uninstall: badge scripts deleted" test ! -e "$U/simple-english-hook"
check "uninstall: flag, score and config deleted" test ! -e "$U/.simple-english-active" -a ! -e "$U/.simple-english-score" -a ! -e "$U/simple-english-hook.json"
check "uninstall: project files deleted" test ! -e "$UP/.claude/ste-mode" -a ! -e "$UP/.claude/ste-config.json"
check "uninstall: empty project .claude removed" test ! -e "$UP/.claude"
check "uninstall: names the plugin uninstall command" has "$out" 'claude plugin uninstall simple-english-hook@simple-english-hook'
check "uninstall: repos note present" has "$out" 'Repos other than this one: delete .claude/ste-mode and .claude/ste-config.json by hand.'
check "uninstall: tells Claude to echo the lines" has "$out" 'Reply with the lines above and nothing else. Do not run tools.'
out="$(hook user-prompt-submit.sh '{"prompt":"/ste uninstall"}' "${UCL[@]}")"
check "uninstall: second run deletes nothing" lacks "$out" 'deleted '
U2="$T/uclaude2"; mkdir -p "$U2"
printf '#!/usr/bin/env bash\ninput=$(cat)\nste_badge=x  # simple-english-hook\nprintf "%%s" "$(printf "%%s" "$input" | jq -r .model.display_name)"\n' > "$U2/statusline.sh"
jq -n --arg c "bash \"$U2/statusline.sh\"" '{statusLine:{type:"command",command:$c}}' > "$U2/settings.json"
hook user-prompt-submit.sh '{"prompt":"/ste uninstall"}' CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_CONFIG_DIR="$U2" CLAUDE_PROJECT_DIR="$UP" >/dev/null
check "uninstall: installer statusline deleted" test ! -e "$U2/statusline.sh"
check "uninstall: statusLine removed from settings.json" jq -e 'has("statusLine") | not' "$U2/settings.json"
check "uninstall: settings backup written" test -e "$U2/settings.json.bak"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
