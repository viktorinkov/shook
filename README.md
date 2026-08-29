<p align="center"><img src="logo.png" alt="SHOOK" width="220"></p>

<p align="center"><strong>SHOOK, a Simple English hook. Claude picks the replies that get the Simple English skill. Most replies never qualify.<br>This plugin applies it to every reply.</strong></p>

<p align="center">Three Claude Code hooks that make <a href="https://github.com/AminBlg/SimpleEnglish">AminBlg/SimpleEnglish</a> always on:<br>the rules at session start, a reminder on every prompt, and a lint gate that sends a failed reply back for a rewrite.<br>The status line shows the mode the whole time: <code>[STE]</code> or <code>[STE:STRICT 0.3]</code>.</p>

<p align="center">
  <a href="evals/results/RESULTS.md"><img src="https://img.shields.io/badge/STE_violations-%E2%88%9277%25_vs_the_skill_alone_(mean_of_6_models)-brightgreen?style=flat" alt="violations vs the skill alone"></a>
  <a href="https://github.com/viktorinkov/shook"><img src="https://img.shields.io/badge/Claude_Code-plugin-blue?style=flat" alt="Claude Code plugin"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-lightgrey?style=flat" alt="MIT"></a>
</p>

## Origin

This plugin is a companion to **[AminBlg/SimpleEnglish](https://github.com/AminBlg/SimpleEnglish)**, the simple-english plugin. That plugin brings ASD-STE100 Simplified Technical English to Claude Code and other agents. It is a prerequisite. The full rule set and the linter `ste_lint.py` come from it at run time. This plugin adds the hooks, the `/ste` command, the status line badge, and the benchmark.

## 📦 Install

First install the [simple-english plugin](https://github.com/AminBlg/SimpleEnglish#-install), the prerequisite. Then install this plugin:

```bash
claude plugin marketplace add viktorinkov/shook
claude plugin install simple-english-hook@simple-english-hook
```

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

## 🚥 The status line

The hooks enforce the mode, so the badge is how you see that the mode is on and how strict it is.

| Badge | Meaning |
|---|---|
| `[STE]` | Mode `on`. |
| `[STE:STRICT 0.3]` | Mode `strict`, with the lint score of the last reply. |
| nothing | Mode `off`. |

- Ask Claude: Install the STE status line badge.
- Or install manually: Run `statusline-install.sh` from this plugin's folder.

## Enable it

The hooks run in every repo. The **mode** decides what they do. The mode has three scopes.

| Scope | How to set it | Where it lives |
|---|---|---|
| Global | `/ste on`, `/ste strict`, `/ste off` | `~/.claude/.simple-english-active` |
| One repo | `/ste project on`, `/ste project strict`, `/ste project off`, `/ste project clear` | `<repo>/.claude/ste-mode` |
| Fixed | `STE_MODE=strict` in the environment, or `"env": {"STE_MODE": "strict"}` in `<repo>/.claude/settings.json` | environment |

Order of precedence: environment, then the repo file, then the global flag, then off. Each harness keeps its own global flag. The repo file and `STE_MODE` apply to all harnesses.

To use it in a team repo, type `/ste project strict` and commit `.claude/ste-mode`. Each team member installs both plugins once.

## 📊 Benchmark

This plugin only changes how often the rules apply, so the comparison that matters is the simple-english skill alone against the hook. The benchmark runs on several Claude models in Claude Code and on GPT models in Codex CLI.

The benchmark sends the same 50 writing prompts (docs, code reviews, error messages, commit messages, incident reports, runbooks) through each arm, one run per prompt. The simple-english plugin's own linter, `ste_lint.py`, counts the rule violations in every reply. Method, full tables, and all raw replies: [`evals/results/RESULTS.md`](evals/results/RESULTS.md).

| Model | n prompts | skill alone (v/100w) | hook on (v/100w) | hook strict (v/100w) | reduction (strict vs skill) |
|---|---:|---:|---:|---:|---:|
| `claude-fable-5` (claude) | 50 | 2.41 | 0.51 | 0.22 | 91% |
| `claude-opus-5` (claude) | 50 | 2.68 | 0.41 | 0.45 | 83% |
| `claude-sonnet-5` (claude) | 50 | 2.38 | 0.47 | 0.32 | 87% |
| `claude-haiku-4-5-20251001` (claude) | 50 | 2.74 | 0.97 | 0.71 | 74% |
| `gpt-5.6-sol` (codex) | 50 | 0.94 | 0.59 | 0.34 | 64% |
| `gpt-5.4-mini` (codex) | 50 | 1.66 | 0.51 | 0.63 | 62% |

The per-model table for Claude Fable 5 shows the three-row shape:

<!-- columns: Arm | Skill fired | Violations / 100 words | Replies with 0 violations | Output tokens per reply -->
| Arm | Skill fired | Violations / 100 words | Replies with 0 violations | Output tokens per reply |
|---|---:|---:|---:|---:|
| skill | 27/50 | 2.41 | 10% | 1224 |
| hook-on | 19/50 | 0.51 | 38% | 1020 |
| hook-strict | 20/50 | 0.22 | 60% | 1361 |

How to read it: Claude alone decides whether the skill fires. On Fable 5, it fired in 27 of 50 replies. The hook applies the rules on every reply. Strict mode adds the gate, blocked 6 of 50 replies on Fable 5, and cut the violations by 91%.

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

## 🔧 Tune the lint gate

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

## Codex CLI

```bash
git clone https://github.com/AminBlg/SimpleEnglish ~/SimpleEnglish
export STE_PLUGIN_DIR=~/SimpleEnglish
codex plugin marketplace add viktorinkov/shook
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
agy plugin install https://github.com/viktorinkov/shook
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
copilot plugin marketplace add viktorinkov/shook
copilot plugin install simple-english-hook@simple-english-hook
```

Put the `export` line in your shell profile.

Toggle: `/simple-english-hook:ste on` or `/simple-english-hook:ste off`. The new mode applies at the next session start.

- Works: `on`. The rules load at session start.
- Does not work: the reminder on each prompt, `strict`, and the badge. Copilot sends no reply text to its stop hook, so the hooks treat `strict` as `on`.

See [GitHub Copilot CLI](docs/other-harnesses.md#github-copilot-cli) in the harness docs.

## Cursor

Cursor loads no plugins, so an install script writes the files that Cursor reads: an always-on rule file and four hooks.

```bash
git clone https://github.com/viktorinkov/shook ~/shook
cd <your-project>
bash ~/shook/cursor-install.sh strict
```

Toggle with `/ste on`, `/ste strict`, `/ste off`, or `/ste status` in the Agent chat, or with `cursor-install.sh <mode>` from the shell. Modes `on` and `strict` both work: the rule file applies the rules to every request, and the `stop` hook sends a failed reply back once. No badge, and no live Cursor session verified it yet. Details: [docs/other-harnesses.md](docs/other-harnesses.md#cursor).

## ❓ FAQ

**Why not just prompt it?** A prompt line is one instruction among many. In the benchmark, the simple-english skill fired on its own in 27 of 50 replies on Fable 5. This plugin does not depend on a decision. It runs every turn.

**Why not the simple-english output style?** The output style is a good one-shot. It has no reminder per turn and no gate. See the five-arm table for Sonnet 5 in [`evals/results/RESULTS.md`](evals/results/RESULTS.md).

**What does strict mode cost?** If a reply fails, one extra rewrite. In the benchmark, strict mode blocked 6 of 50 replies on Fable 5. See the token column.

## Update

```bash
claude plugin marketplace update simple-english-hook
claude plugin update simple-english-hook@simple-english-hook
```

## 🧹 Uninstall

1. Type `/ste uninstall`. It removes the status line badge, the state files, and the mode and config files in the current repo.
2. Run `claude plugin uninstall simple-english-hook@simple-english-hook`.

If other repos have a `.claude/ste-mode` or `.claude/ste-config.json` file, delete those by hand. To remove the [simple-english plugin](https://github.com/AminBlg/SimpleEnglish) too, follow the steps in its README.

---

MIT. Not affiliated with ASD or STEMG. ASD-STE100 is a registered trademark of ASD.
