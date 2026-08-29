<p align="center"><strong>Claude picks the replies that get the Simple English skill. Most replies never qualify.<br>This plugin applies it to every reply.</strong></p>

<p align="center">Three Claude Code hooks that make <a href="https://github.com/AminBlg/SimpleEnglish">AminBlg/SimpleEnglish</a> always on:<br>the rules at session start, a reminder on every prompt, and a lint gate that sends a reply back until it passes.<br>No rule text lives here. The plugin supplies it at run time.</p>

<p align="center">
  <a href="evals/results/RESULTS.md"><img src="https://img.shields.io/badge/skill_fired_on_its_own-24_of_50_replies-orange?style=flat" alt="skill fired on its own"></a>
  <a href="evals/results/RESULTS.md"><img src="https://img.shields.io/badge/STE_violations-%E2%88%9287%25_with_the_hook-brightgreen?style=flat" alt="violations with the hook"></a>
  <a href="https://github.com/viktorinkov/simple-english-hook"><img src="https://img.shields.io/badge/Claude_Code-plugin-blue?style=flat" alt="Claude Code plugin"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-lightgrey?style=flat" alt="MIT"></a>
</p>

## Before / after

Same prompt, same model, real unedited output. The prompt asked Claude to explain a failed Python test to a junior developer.

<table>
<tr>
<th width="50%">Plugin installed. The skill did not fire.</th>
<th width="50%">Hook on</th>
</tr>
<tr>
<td valign="top">

> Since `None` has no `.status` attribute, `service.sync` raises an `AttributeError` before it ever gets to return a `result` — so the test fails with that exception, not with a failed assertion on `result.ok`.
>
> **The fix:** the mock needs to return an object that actually has a `.status` attribute, e.g.:

The quoted sentence: 32 words. The longest sentence in the reply: 55 words. One `e.g.`.

</td>
<td valign="top">

> Here is the sequence of events:
>
> 1. `service.sync(client)` calls `client.upload()`.
> 2. The mock returns `None`, per the test setup.
> 3. `service.sync` then tries to read `.status` from that return value.
> 4. Python raises `AttributeError: 'NoneType' object has no attribute 'status'`.
>
> The test never reaches the `assert result.ok` line.

The longest sentence: 16 words. Zero violations in 100 words.

</td>
</tr>
</table>

Strict mode catches the slips that the reminder misses. When a reply fails the linter, the Stop hook sends it back. This is the linter on a real baseline reply from the benchmark:

```
STE LINT FAILED (8 violations in 234 words, 3.42 per 100 words; longest sentence 35 words).
Found: sentence_over_limit=2, contraction=4, trailing_condition=2. Rewrite your whole last reply ...
```

Claude rewrites once. After the rewrite passes, the status line shows `[STE:STRICT 0.0]`.

## Install

```bash
claude plugin marketplace add AminBlg/SimpleEnglish
claude plugin install simple-english@simple-english
claude plugin marketplace add viktorinkov/simple-english-hook
claude plugin install simple-english-hook@simple-english-hook
```

Start a new session. Type `/ste on` for the reminder on every prompt, or `/ste strict` for the reminder plus the lint gate. Type `/ste off` to stop. Type `/ste project strict` to limit the mode to one repo.

Requirements: Claude Code, `jq`, and `python3` (strict mode only). No Node. No telemetry. Six shell files.

The same hooks run in Codex CLI and Antigravity CLI, with strict mode. In Copilot CLI, the rules load at session start only. See [`docs/other-harnesses.md`](docs/other-harnesses.md).

## Numbers

50 prompts, one run per arm, `claude-sonnet-5`. Scored with the plugin's own `ste_lint.py`. Full table, method, and every raw reply: [`evals/results/RESULTS.md`](evals/results/RESULTS.md).

| Arm | n | Skill fired | Violations / 100 words (mean) | median | Replies with 0 violations | Reduction vs baseline | Mean words | Mean output tokens | Strict blocks | Cost USD |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 50 | 0/50 | 3.61 | 3.73 | 22% | 0% | 145 | 464 | 0 | 1.29 |
| skill | 50 | 24/50 | 2.38 | 2.31 | 32% | 34% | 136 | 1011 | 0 | 2.79 |
| style | 50 | 29/50 | 0.85 | 0.00 | 56% | 76% | 119 | 883 | 0 | 2.96 |
| hook-on | 50 | 12/50 | 0.47 | 0.00 | 54% | 87% | 110 | 687 | 0 | 2.19 |
| hook-strict | 50 | 7/50 | 0.32 | 0.00 | 66% | 91% | 100 | 1237 | 6 | 2.26 |
|---|---:|---:|---:|---:|---:|

How to read it: the skill fired on its own in 24 of 50 replies. The output style is a good one-shot. The hook adds a reminder next to every prompt, and strict mode adds the gate. Strict mode blocked 6 of 50 replies and used about 550 more output tokens per reply than `hook-on`.

Read the table with care. The linter is a regex pass. It undercounts and it cannot judge meaning. The numbers compare arms against each other. They are not a compliance score. No tool can certify ASD-STE100 compliance.

Reproduce: `python3 evals/bench.py`. The script needs only a logged-in Claude Code CLI.

## How it works

| Hook | Event | Action |
|---|---|---|
| `SessionStart` | New session, resume, clear, compact | Loads the full STE rule set as context. |
| `UserPromptSubmit` | Every prompt | Adds a 74-word STE reminder. Handles `/ste` commands. |
| `Stop` | End of every reply, `strict` mode only | Runs `ste_lint.py` on the reply. If the reply fails, Claude must rewrite it once. |
| Status line (optional) | Always | Shows `[STE]`, or `[STE:STRICT 0.3]` with the last score. |

The reminder on every prompt is the part that an output style cannot do. A system prompt is read once. A reminder sits next to the newest message, every turn.

## Enable it

The hooks run in every repo. The **mode** decides what they do. The mode has three scopes.

| Scope | How to set it | Where it lives |
|---|---|---|
| Global | `/ste on`, `/ste strict`, `/ste off` | `~/.claude/.simple-english-active` |
| One repo | `/ste project on`, `/ste project strict`, `/ste project off`, `/ste project clear` | `<repo>/.claude/ste-mode` |
| Fixed | `STE_MODE=strict` in the environment, or `"env": {"STE_MODE": "strict"}` in `<repo>/.claude/settings.json` | environment |

Order of precedence: environment, then the repo file, then the global flag, then off. `/ste status` shows the current mode and its source.

To use it in a team repo, type `/ste project strict` and commit `.claude/ste-mode`. Each team member installs the plugin once.

### The status line badge

A plugin cannot change the status line, so this step is by hand. Ask Claude: *install the STE status line badge*. Claude runs `statusline-install.sh` from the plugin folder. The script adds one line to your status line script. If you have no status line, the script creates one.

## Tune the lint gate

When all three conditions are true, the gate blocks the reply:

- The reply has at least `STE_MIN_WORDS` words (default 40).
- The reply has at least `STE_MIN_TOTAL` violations (default 2).
- The density is above `STE_MAX_PER_100W` violations per 100 words (default 1.0).

Set these as environment variables, or edit the policy block in `hooks/stop-gate.sh`. A tight gate makes Claude rewrite short, correct replies. A loose gate lets slop through. The gate runs at most one rewrite per turn.

## What it does not touch

- Code blocks, identifiers, file paths, CLI commands, and quoted error messages. The rules and the linter skip them.
- Code that Claude writes. The rules apply to prose only.
- Marketing copy or brand voice that you ask for.
- Any repo with `/ste project off`. Any session with `/ste off`.

STE is flat by design. Use it for docs, reviews, runbooks, error messages, and explanations. Turn it off for a blog post.

## FAQ

**Why not just prompt it?** A prompt line is one instruction among many. In the benchmark, the skill fired on its own in 24 of 50 replies. The hook does not depend on a decision. It runs every turn.

**Why not the plugin's output style?** The output style is a good one-shot. It has no reminder per turn and no gate. See the `style` row in the table.

**What does strict mode cost?** If a reply fails, one extra rewrite. In the benchmark, strict mode blocked 6 of 50 replies. See the token column.

**Does it make my docs STE compliant?** No. Nothing does. The gate catches the mechanical slips. Word-level rulings live in the official standard.

**Does it work outside Claude Code?** See [`docs/other-harnesses.md`](docs/other-harnesses.md).

## Update

```bash
claude plugin marketplace update simple-english-hook
claude plugin update simple-english-hook@simple-english-hook
```

## Uninstall

1. Run `claude plugin uninstall simple-english-hook@simple-english-hook`.
2. If you installed the badge, remove the line that ends with `# simple-english-hook` from your status line script.
3. Delete `~/.claude/.simple-english-active`, `~/.claude/.simple-english-score`, and `~/.claude/simple-english-hook/`.
4. Delete `.claude/ste-mode` from any repo that has one.

## Origin

This project is a companion to **[AminBlg/SimpleEnglish](https://github.com/AminBlg/SimpleEnglish)**. That plugin brings ASD-STE100 Simplified Technical English to Claude Code and other agents. All rule text and the linter come from that plugin at run time. This repo adds the hooks, the `/ste` command, the status line badge, and the benchmark. MIT. Not affiliated with ASD or STEMG. ASD-STE100 is a registered trademark of ASD.
