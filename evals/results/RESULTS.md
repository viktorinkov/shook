# Results

Model: `claude-sonnet-5`. Prompts: 50. Scorer: the simple-english plugin's `ste_lint.py` (regex pass, undercounts, comparable between arms only).

| Arm | n | Skill fired | Violations / 100 words (mean) | median | Replies with 0 violations | Reduction vs baseline | Mean words | Mean output tokens | Strict blocks | Cost USD |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 50 | 0/50 | 3.61 | 3.73 | 22% | 0% | 145 | 464 | 0 | 1.29 |
| skill | 50 | 24/50 | 2.38 | 2.31 | 32% | 34% | 136 | 1011 | 0 | 2.79 |
| style | 50 | 29/50 | 0.85 | 0.00 | 56% | 76% | 119 | 883 | 0 | 2.96 |
| hook-on | 50 | 12/50 | 0.47 | 0.00 | 54% | 87% | 110 | 687 | 0 | 2.19 |
| hook-strict | 50 | 7/50 | 0.32 | 0.00 | 66% | 91% | 100 | 1237 | 6 | 2.26 |

## Per category (mean violations / 100 words)

| Category | baseline | skill | style | hook-on | hook-strict |
|---|---:|---:|---:|---:|---:|
| commit | 0.00 | 1.05 | 0.00 | 0.00 | 0.00 |
| design | 5.88 | 6.02 | 3.29 | 0.47 | 0.34 |
| docs | 3.01 | 1.61 | 0.50 | 0.42 | 0.21 |
| error | 2.00 | 0.60 | 0.22 | 0.00 | 0.00 |
| explain | 4.40 | 3.11 | 2.06 | 0.61 | 0.43 |
| incident | 3.89 | 1.81 | 0.19 | 0.26 | 0.54 |
| release | 3.29 | 0.82 | 1.50 | 1.14 | 0.93 |
| review | 5.66 | 4.42 | 0.81 | 0.80 | 0.33 |
| runbook | 3.84 | 1.42 | 0.22 | 0.73 | 0.65 |

## Method

Each prompt ran once per arm with `claude -p --setting-sources project --tools Skill`, so no user settings, hooks, or other plugins were loaded. `skill` and `style` load the simple-english plugin with `--plugin-dir`. `style` appends the plugin's output style text as system prompt. `hook-on` and `hook-strict` also load this plugin with `--plugin-dir` and set `STE_MODE`. `Skill fired` counts replies where Claude invoked the simple-english skill. `Strict blocks` counts replies the Stop hook sent back for a rewrite. Raw runs: `results/raw/`.
