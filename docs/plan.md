# Plan

Based on the virality research of ponytail and SimpleEnglish (2026-08-28).

## Done

- Plugin install in two commands. No edits to `settings.json`.
- Per-repo mode file `.claude/ste-mode`. Three scopes: env, repo, global.
- Strict mode: lint gate with one rewrite per turn.
- Badge with the last lint score: `[STE:STRICT 0.3]`.
- Benchmark runner: `evals/bench.py`, 50 prompts, 5 arms.

## In progress

- Full benchmark run and the numbers in the README.
- README first screen: hook line, badges, real before/after, four install commands.
- FAQ and "What it does not touch".
- Codex, Copilot CLI, and Gemini CLI support. Docs in `docs/other-harnesses.md`.

## Future

### Upstream outreach (research item 7)

Goal: a link from AminBlg/SimpleEnglish (2,900 stars) to this repo.

1. Comment on upstream PR #14 ("Auto-load Simple English in Claude Code and Codex"). Point to this repo as the always-on path with a lint gate.
2. Comment on upstream issue #18 (combine with caveman).
3. Open a small PR to the upstream README: a "Companions" line with a link here.
4. Offer the lint gate as a contribution to upstream `evals/`.

Viktor posts these. Claude drafts the text on request.

### Launch

1. Submit to jqueryscript/awesome-claude-code, VoltAgent/awesome-agent-skills, claudepluginhub, skillsllm.
2. Record a before/after terminal clip: no plugin, skill silent, hook on, strict block and rewrite.
3. Show HN on a Tuesday to Thursday, 14:00 to 16:00 UTC. Reddit r/ClaudeCode the same morning. Reply to every comment in the first three hours.
4. Tag v1.0.0 with a release note.
5. Later: export the gate as a pre-commit or CI check for `.md` files.

## Not planned

- README lint badge in CI (research item 3). Rejected.
- Rename (research item 8). Rejected.
