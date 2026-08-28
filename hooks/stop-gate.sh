#!/usr/bin/env bash
# Stop hook (AfterAgent on Gemini CLI): in "strict" mode, lint the last reply. Block the stop when it fails.
# The model then gets the reason and rewrites the reply. Runs at most one retry per turn.
# Copilot CLI's agentStop event carries no reply text, so this hook is a no-op there.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

[ "$STE_HARNESS_NAME" = "copilot" ] && exit 0

input="$(cat)"
ste_project_from_input "$input"
[ "$(ste_mode)" = "strict" ] || exit 0

# The harness sets stop_hook_active when a Stop hook already forced a continuation.
# Exit here, or the rewrite could loop forever.
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0

# Claude Code and Codex send last_assistant_message. Gemini CLI sends prompt_response.
message="$(printf '%s' "$input" | jq -r '.last_assistant_message // .prompt_response // ""')"
[ -z "$message" ] && exit 0

lint="$(ste_lint_script)" || exit 0
report="$(printf '%s' "$message" | python3 "$lint" --type "${STE_LINT_TYPE:-descriptive}" - 2>/dev/null)" || exit 0

# Record the score for the status line badge: "<per100> <total> <words>".
printf '%s' "$report" | jq -r '"\(.violations_per_100w) \(.violations_total) \(.words)"' > "$STE_SCORE" 2>/dev/null || true
words="$(printf '%s' "$report" | jq -r '.words')"
total="$(printf '%s' "$report" | jq -r '.violations_total')"
per100="$(printf '%s' "$report" | jq -r '.violations_per_100w')"

# ---- Gate policy -----------------------------------------------------------
# This is the one decision that shapes how strict the mode feels.
# The linter is a regex pass. It undercounts, and it flags some valid words
# (for example "could" in a quoted user sentence). A gate that is too tight
# makes Claude rewrite short, correct replies. A gate that is too loose lets
# slop through. Defaults below: skip short replies, allow one slip, block when
# the density of violations is above STE_MAX_PER_100W.
min_words="${STE_MIN_WORDS:-40}"
max_per100="${STE_MAX_PER_100W:-1.0}"
min_total="${STE_MIN_TOTAL:-2}"

should_block=$(python3 - "$words" "$total" "$per100" "$min_words" "$max_per100" "$min_total" <<'PY'
import sys
words, total, per100, min_words, max_per100, min_total = map(float, sys.argv[1:])
print("yes" if words >= min_words and total >= min_total and per100 > max_per100 else "no")
PY
)
[ "$should_block" = "yes" ] || exit 0

detail="$(printf '%s' "$report" | jq -r '.violations | to_entries | map(select(.value > 0)) | map("\(.key)=\(.value)") | join(", ")')"
longest="$(printf '%s' "$report" | jq -r '.longest_sentence_words')"

reason="STE LINT FAILED (${total} violations in ${words} words, ${per100} per 100 words; longest sentence ${longest} words). Found: ${detail}. Rewrite your whole last reply in ASD-STE100 Simplified Technical English. Keep every fact and every code block unchanged. Fix each listed violation: split long sentences, remove contractions and should/would/may/might/could, replace present perfect and -ing clauses with simple tenses, remove semicolons and filler words, and use one word per meaning. Do not mention this lint message. Output only the rewritten reply."

[ -n "${STE_LOG:-}" ] && printf '%s block %s %s\n' "$(date -u +%FT%TZ)" "$(printf '%s' "$input" | jq -r '.session_id // "-"')" "$per100" >> "$STE_LOG"
# Claude Code, Codex and Gemini CLI all read {"decision":"block","reason":...}.
jq -n --arg r "$reason" '{decision:"block", reason:$r}'
exit 0
