# Results

Scorer: the simple-english plugin's `ste_lint.py`. It is a regex pass. It undercounts, and the numbers compare arms only.
Prompts: 50. Models: `claude-haiku-4-5-20251001` (claude), `claude-opus-5` (claude), `claude-sonnet-5` (claude).

## Cross-model summary

| Model | n prompts | skill alone (v/100w) | hook on (v/100w) | hook strict (v/100w) | reduction (strict vs skill) |
|---|---:|---:|---:|---:|---:|
| `claude-haiku-4-5-20251001` (claude) | 50 | 2.74 | 0.97 | 0.71 | 74% |
| `claude-opus-5` (claude) | 50 | 2.68 | 0.41 | 0.45 | 83% |
| `claude-sonnet-5` (claude) | 50 | 2.38 | 0.47 | 0.32 | 87% |

## Per model

### `claude-haiku-4-5-20251001` (claude)

| Arm | Skill fired | Violations / 100 words | Replies with 0 violations | Output tokens per reply |
|---|---:|---:|---:|---:|
| skill | 24/50 | 2.74 | 10% | 2523 |
| hook-on | 3/50 | 0.97 | 44% | 1869 |
| hook-strict | 2/50 | 0.71 | 58% | 3227 |

Reduction vs the skill alone: hook-on −65%, hook-strict −74%.

### `claude-opus-5` (claude)

| Arm | Skill fired | Violations / 100 words | Replies with 0 violations | Output tokens per reply |
|---|---:|---:|---:|---:|
| skill | 25/50 | 2.68 | 14% | 1514 |
| hook-on | 15/50 | 0.41 | 48% | 1491 |
| hook-strict | 15/50 | 0.45 | 50% | 1986 |

Reduction vs the skill alone: hook-on −85%, hook-strict −83%.

### `claude-sonnet-5` (claude)

| Arm | Skill fired | Violations / 100 words | Replies with 0 violations | Output tokens per reply |
|---|---:|---:|---:|---:|
| skill | 24/50 | 2.38 | 32% | 1011 |
| hook-on | 12/50 | 0.47 | 54% | 687 |
| hook-strict | 7/50 | 0.32 | 66% | 1237 |

Reduction vs the skill alone: hook-on −80%, hook-strict −87%.

## Full five-arm table

This table stays as the receipt for the reference arms. `baseline` has no plugin. `style` uses the plugin output style as a system prompt.

### `claude-sonnet-5` (claude)

| Arm | n | Skill fired | Violations / 100 words (mean) | median | Replies with 0 violations | Reduction vs baseline | Mean words | Mean output tokens | Strict blocks | Cost USD |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 50 | 0/50 | 3.61 | 3.73 | 22% | 0% | 145 | 464 | 0 | 1.29 |
| skill | 50 | 24/50 | 2.38 | 2.31 | 32% | 34% | 136 | 1011 | 0 | 2.79 |
| style | 50 | 29/50 | 0.85 | 0.00 | 56% | 76% | 119 | 883 | 0 | 2.96 |
| hook-on | 50 | 12/50 | 0.47 | 0.00 | 54% | 87% | 110 | 687 | 0 | 2.19 |
| hook-strict | 50 | 7/50 | 0.32 | 0.00 | 66% | 91% | 100 | 1237 | 6 | 2.26 |

## Method

Each prompt ran once per arm with `claude -p --setting-sources project --tools Skill`, so no user settings, hooks, or other plugins were loaded. `skill` and `style` load the simple-english plugin with `--plugin-dir`. `style` appends the plugin's output style text as system prompt. `hook-on` and `hook-strict` also load this plugin with `--plugin-dir` and set `STE_MODE`. `Skill fired` counts replies where Claude invoked the simple-english skill. `Strict blocks` counts replies the Stop hook sent back for a rewrite. Raw runs: `results/raw/`.

Models: `claude-haiku-4-5-20251001` (claude), `claude-opus-5` (claude), `claude-sonnet-5` (claude). The `skill` arm against the two hook arms is the comparison that matters. The only thing this plugin changes is how often the rules apply. The `baseline` and `style` arms are a reference and ran for `claude-sonnet-5` (claude) only. `Output tokens per reply` is the mean of `output_tokens` from the CLI usage report. In `hook-strict` it includes the rewrite. Raw record names follow `<harness>__<model>__<arm>__<id>.json`. A `codex` harness writes the same schema from Codex CLI with `evals/codex_bench.py`.
