<p align="center"><strong>Claude picks the replies that get the Simple English skill. Most replies never qualify.<br>This plugin applies it to every reply.</strong></p>

<p align="center">Three Claude Code hooks that make <a href="https://github.com/AminBlg/SimpleEnglish">AminBlg/SimpleEnglish</a> always on:<br>the rules at session start, a reminder on every prompt, and a lint gate that sends a failed reply back for a rewrite.<br>The full rule set comes from the simple-english plugin at run time.</p>

<p align="center">
  <a href="evals/results/RESULTS.md"><img src="https://img.shields.io/badge/STE_violations-%E2%88%92{{REDUCTION_STRICT}}%25_vs_the_skill_alone-brightgreen?style=flat" alt="violations vs the skill alone"></a>
  <a href="https://github.com/viktorinkov/simple-english-hook"><img src="https://img.shields.io/badge/Claude_Code-plugin-blue?style=flat" alt="Claude Code plugin"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-lightgrey?style=flat" alt="MIT"></a>
</p>

## Origin

This plugin is a companion to **[AminBlg/SimpleEnglish](https://github.com/AminBlg/SimpleEnglish)**, the simple-english plugin. That plugin brings ASD-STE100 Simplified Technical English to Claude Code and other agents. It is a prerequisite. The full rule set and the linter `ste_lint.py` come from it at run time. This plugin adds the hooks, the `/ste` command, the status line badge, and the benchmark.

## Install

```bash
claude plugin marketplace add AminBlg/SimpleEnglish
claude plugin install simple-english@simple-english
claude plugin marketplace add viktorinkov/simple-english-hook
claude plugin install simple-english-hook@simple-english-hook
```

The first two commands install the simple-english plugin, the prerequisite. The last two install this plugin.

Requirements: Claude Code, the simple-english plugin, `jq`, and `python3` (strict mode only). No Node. No telemetry. Six shell files.

Start a new session.

## Use

| Command | What it does |
|---|---|
| `/ste on` | Loads the rules at session start and adds the reminder on every prompt. |
| `/ste strict` | Same as `on`, plus the lint gate on every reply. |
| `/ste off` | Stops the hooks. |
| `/ste status` | Shows the current mode and its source. |
| `/ste project <mode>` | Sets `on`, `strict`, or `off` for the current repo only. `/ste project clear` removes it. |
| `/ste config` | Shows every lint gate setting, its value, and its source. |
| `/ste set <key> <value>` | Writes a lint gate setting. See [Tune the lint gate](#tune-the-lint-gate). |
| `/ste uninstall` | Removes the badge and the state files. Then run the plugin uninstall command. |

## Codex CLI

```bash
git clone https://github.com/AminBlg/SimpleEnglish ~/SimpleEnglish
export STE_PLUGIN_DIR=~/SimpleEnglish
codex plugin marketplace add viktorinkov/simple-english-hook
codex plugin add simple-english-hook@simple-english-hook
```

Put the `export` line in your shell profile. Codex does not install the simple-english plugin, so the hooks read the rules and the linter from the clone.

Toggle: `$ste on`, `$ste strict`, `$ste off`, or `$ste status`. The `$` opens the Codex skill picker.

- Works: `on` and `strict`. The rules load at session start, each prompt gets the reminder, and the Stop hook sends a failed reply back once.
- Does not work: the status line badge. Codex has no status line. The mode shows as a system message at session start and after each toggle.

At the first start, Codex asks you to review the hooks. See [Codex CLI](docs/other-harnesses.md#codex-cli) in the harness docs.

## Antigravity CLI

```bash
git clone https://github.com/AminBlg/SimpleEnglish ~/SimpleEnglish
export STE_PLUGIN_DIR=~/SimpleEnglish
agy plugin install https://github.com/viktorinkov/simple-english-hook
```

Put the `export` line in your shell profile.

Toggle: `/ste on`, `/ste strict`, `/ste off`, or `/ste status`.

- Works: `on` and `strict`. The rules load at session start, each model call gets the reminder, and the Stop hook lints the reply from the transcript.
- Does not work: the badge. In print mode (`agy -p`) outside a project, the hooks do not read the per-repo file. Use the global flag or `STE_MODE`.

See [Antigravity CLI](docs/other-harnesses.md#antigravity-cli) in the harness docs.

## Copilot CLI

```bash
git clone https://github.com/AminBlg/SimpleEnglish ~/SimpleEnglish
export STE_PLUGIN_DIR=~/SimpleEnglish
copilot plugin marketplace add viktorinkov/simple-english-hook
copilot plugin install simple-english-hook@simple-english-hook
```

Put the `export` line in your shell profile.

Toggle: `/simple-english-hook:ste on` or `/simple-english-hook:ste off`. The new mode applies at the next session start.

- Works: `on`. The rules load at session start.
- Does not work: the reminder on each prompt, `strict`, and the badge. Copilot sends no reply text to its stop hook, so the hooks treat `strict` as `on`.

See [GitHub Copilot CLI](docs/other-harnesses.md#github-copilot-cli) in the harness docs.

## Cursor

{{CURSOR_SECTION}}

## Enable it

The hooks run in every repo. The **mode** decides what they do. The mode has three scopes.

| Scope | How to set it | Where it lives |
|---|---|---|
| Global | `/ste on`, `/ste strict`, `/ste off` | `~/.claude/.simple-english-active` |
| One repo | `/ste project on`, `/ste project strict`, `/ste project off`, `/ste project clear` | `<repo>/.claude/ste-mode` |
| Fixed | `STE_MODE=strict` in the environment, or `"env": {"STE_MODE": "strict"}` in `<repo>/.claude/settings.json` | environment |

Order of precedence: environment, then the repo file, then the global flag, then off. Each harness keeps its own global flag. The repo file and `STE_MODE` apply to all harnesses.

To use it in a team repo, type `/ste project strict` and commit `.claude/ste-mode`. Each team member installs both plugins once.

### The status line badge

A plugin cannot change the status line, so this step is by hand. When the mode is on, ask Claude: *install the STE status line badge*. Claude runs `statusline-install.sh` from this plugin's folder. The script adds one line to your status line script. If you have no status line, the script creates one. The badge shows the lint score in strict mode only.

## Numbers

This plugin only changes how often the rules apply, so the comparison that matters is the simple-english skill alone against the hook. The benchmark runs on several Claude models in Claude Code and on GPT models in Codex CLI.

One run per prompt and arm. Scored with the simple-english plugin's own `ste_lint.py`.

{{MODEL_TABLE}}

The per-model table for Claude Sonnet 5 shows the three-row shape:

<!-- columns: Arm | Skill fired | Violations / 100 words | Replies with 0 violations | Output tokens per reply -->
{{SONNET_TABLE}}

How to read it: Claude alone decides whether the skill fires. On Sonnet 5, it fired in {{SKILL_FIRED}} of {{N}} replies. The hook applies the rules on every reply. Strict mode adds the gate and blocked {{BLOCKS}} of {{N}} replies on Sonnet 5.

Read the tables with care. The linter is a regex pass. It undercounts and it cannot judge meaning. The numbers compare arms against each other. They are not a compliance score. No tool can certify ASD-STE100 compliance.

Reproduce: `python3 evals/bench.py` for Claude Code, and `python3 evals/codex_bench.py` for Codex. The scripts need a logged-in CLI and the installed simple-english plugin. Full tables, including a no-plugin baseline and the output-style arm for Sonnet 5, live in [`evals/results/RESULTS.md`](evals/results/RESULTS.md).

## How it works

| Hook | Event | Action |
|---|---|---|
| `SessionStart` | New session, resume, clear, compact | Loads the full rule set from the simple-english plugin as context. |
| `UserPromptSubmit` | Every prompt | Adds a 74-word STE reminder. Handles `/ste` commands. |
| `Stop` | End of every reply, `strict` mode only | Runs the simple-english linter `ste_lint.py` on the reply. If the reply fails, Claude must rewrite it once. |
| Status line (optional) | Always | Shows `[STE]` in `on` mode, or `[STE:STRICT 0.3]` with the last lint score in `strict` mode. Shows nothing in `off` mode. |

In strict mode, a failed reply goes back to Claude with a message like this one from the benchmark:

```
STE LINT FAILED (8 violations in 234 words, 3.42 per 100 words; longest sentence 35 words).
Found: sentence_over_limit=2, contraction=4, trailing_condition=2. Rewrite your whole last reply ...
```

Claude rewrites the reply once per turn.

The reminder on every prompt is the part that an output style cannot do. A system prompt is read once. A reminder sits next to the newest message, every turn.

## Tune the lint gate

When all three conditions are true, the gate blocks the reply:

- The reply has at least `min-words` words (default 40).
- The reply has at least `min-total` violations (default 2).
- The density is above `max-per-100w` violations per 100 words (default 1.0).

A tight gate makes Claude rewrite short, correct replies. A loose gate lets slop through. The gate runs at most one rewrite per turn.

| Command | What it does |
|---|---|
| `/ste config` | Shows every setting, its value, and its source (env, project, global, default). |
| `/ste set <key> <value>` | Writes the global setting. |
| `/ste project set <key> <value>` | Writes the setting for the current repo. |
| `/ste unset <key>`, `/ste project unset <key>` | Removes one setting. |

Keys: `min-words`, `min-total`, `max-per-100w`, and `lint-type` (`descriptive` or `procedural`, default `descriptive`).

Files: global `~/.claude/simple-english-hook.json`, per repo `<repo>/.claude/ste-config.json`. The repo file is safe to commit. Precedence: environment variable, then the repo file, then the global file, then the default. For CI and scripts, the environment variables `STE_MIN_WORDS`, `STE_MIN_TOTAL`, `STE_MAX_PER_100W`, and `STE_LINT_TYPE` still work.

## What it does not touch

- Code blocks, identifiers, file paths, CLI commands, and quoted error messages. The rules and the linter skip them.
- Code that Claude writes. The rules apply to prose only.
- Marketing copy or brand voice that you ask for.
- Any repo with `/ste project off`. Any session with `/ste off`.

STE is flat by design. Use it for docs, reviews, runbooks, error messages, and explanations. Turn it off for a blog post.

## FAQ

**Why not just prompt it?** A prompt line is one instruction among many. In the benchmark, the simple-english skill fired on its own in {{SKILL_FIRED}} of {{N}} replies on Sonnet 5. This plugin does not depend on a decision. It runs every turn.

**Why not the simple-english output style?** The output style is a good one-shot. It has no reminder per turn and no gate. See the five-arm table for Sonnet 5 in [`evals/results/RESULTS.md`](evals/results/RESULTS.md).

**What does strict mode cost?** If a reply fails, one extra rewrite. In the benchmark, strict mode blocked {{BLOCKS}} of {{N}} replies on Sonnet 5. See the token column.

## Update

```bash
claude plugin marketplace update simple-english-hook
claude plugin update simple-english-hook@simple-english-hook
```

## Uninstall

1. Type `/ste uninstall`. It removes the status line badge, the state files, and the mode and config files in the current repo.
2. Run `claude plugin uninstall simple-english-hook@simple-english-hook`.

If other repos have a `.claude/ste-mode` or `.claude/ste-config.json` file, delete those by hand. To remove the simple-english plugin too, run `claude plugin uninstall simple-english@simple-english`.

---

MIT. Not affiliated with ASD or STEMG. ASD-STE100 is a registered trademark of ASD.
