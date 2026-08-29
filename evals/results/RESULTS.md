# Results

Scorer: the simple-english plugin's `ste_lint.py`. It is a regex pass. It undercounts, and the numbers compare arms only.
Prompts: 50. Models: `claude-fable-5` (claude), `claude-haiku-4-5-20251001` (claude), `claude-opus-5` (claude), `claude-sonnet-5` (claude), `gpt-5.4-mini` (codex), `gpt-5.6-sol` (codex).

## Cross-model summary

| Model | n prompts | skill alone (v/100w) | hook on (v/100w) | hook strict (v/100w) | reduction (strict vs skill) |
|---|---:|---:|---:|---:|---:|
| `claude-fable-5` (claude) | 50 | 2.41 | 0.51 | 0.22 | 91% |
| `claude-haiku-4-5-20251001` (claude) | 50 | 2.74 | 0.97 | 0.71 | 74% |
| `claude-opus-5` (claude) | 50 | 2.68 | 0.41 | 0.45 | 83% |
| `claude-sonnet-5` (claude) | 50 | 2.38 | 0.47 | 0.32 | 87% |
| `gpt-5.4-mini` (codex) | 50 | 1.66 | 0.51 | 0.63 | 62% |
| `gpt-5.6-sol` (codex) | 50 | 0.94 | 0.59 | 0.34 | 64% |

## Per model

Every arm that ran for the model, with all columns. The reduction column compares against the `skill` arm.

### `claude-fable-5` (claude)

| Arm | n | Skill fired | Violations / 100 words (mean) | median | Replies with 0 violations | Reduction vs skill | Mean words | Mean output tokens | Strict blocks | Cost USD |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| skill | 50 | 27/50 | 2.41 | 2.17 | 10% | — | 340 | 1224 | 0 | 10.84 |
| hook-on | 50 | 19/50 | 0.51 | 0.40 | 38% | −79% | 273 | 1020 | 0 | 10.08 |
| hook-strict | 50 | 20/50 | 0.22 | 0.00 | 60% | −91% | 261 | 1361 | 6 | 11.31 |

### `claude-haiku-4-5-20251001` (claude)

| Arm | n | Skill fired | Violations / 100 words (mean) | median | Replies with 0 violations | Reduction vs skill | Mean words | Mean output tokens | Strict blocks | Cost USD |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| skill | 50 | 24/50 | 2.74 | 2.25 | 10% | — | 171 | 2523 | 0 | 1.47 |
| hook-on | 50 | 3/50 | 0.97 | 0.62 | 44% | −65% | 120 | 1869 | 0 | 1.07 |
| hook-strict | 50 | 2/50 | 0.71 | 0.00 | 58% | −74% | 107 | 3227 | 11 | 1.46 |

### `claude-opus-5` (claude)

| Arm | n | Skill fired | Violations / 100 words (mean) | median | Replies with 0 violations | Reduction vs skill | Mean words | Mean output tokens | Strict blocks | Cost USD |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| skill | 50 | 25/50 | 2.68 | 2.66 | 14% | — | 299 | 1514 | 0 | 6.50 |
| hook-on | 50 | 15/50 | 0.41 | 0.23 | 48% | −85% | 228 | 1491 | 0 | 6.14 |
| hook-strict | 50 | 15/50 | 0.45 | 0.12 | 50% | −83% | 233 | 1986 | 2 | 6.55 |

### `claude-sonnet-5` (claude)

| Arm | n | Skill fired | Violations / 100 words (mean) | median | Replies with 0 violations | Reduction vs skill | Mean words | Mean output tokens | Strict blocks | Cost USD |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 50 | 0/50 | 3.61 | 3.73 | 22% | +51% | 145 | 464 | 0 | 1.29 |
| skill | 50 | 24/50 | 2.38 | 2.31 | 32% | — | 136 | 1011 | 0 | 2.79 |
| style | 50 | 29/50 | 0.85 | 0.00 | 56% | −64% | 119 | 883 | 0 | 2.96 |
| hook-on | 50 | 12/50 | 0.47 | 0.00 | 54% | −80% | 110 | 687 | 0 | 2.19 |
| hook-strict | 50 | 7/50 | 0.32 | 0.00 | 66% | −87% | 100 | 1237 | 6 | 2.26 |

### `gpt-5.4-mini` (codex)

| Arm | n | Skill fired | Violations / 100 words (mean) | median | Replies with 0 violations | Reduction vs skill | Mean words | Mean output tokens | Strict blocks | Cost USD |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| skill | 50 | 4/50 | 1.66 | 1.32 | 34% | — | 100 | 228 | 0 | 0.00 |
| hook-on | 50 | 0/50 | 0.51 | 0.00 | 70% | −69% | 63 | 133 | 0 | 0.00 |
| hook-strict | 50 | 0/50 | 0.63 | 0.00 | 74% | −62% | 55 | 158 | 8 | 0.00 |

### `gpt-5.6-sol` (codex)

| Arm | n | Skill fired | Violations / 100 words (mean) | median | Replies with 0 violations | Reduction vs skill | Mean words | Mean output tokens | Strict blocks | Cost USD |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| skill | 50 | 36/50 | 0.94 | 0.00 | 62% | — | 73 | 509 | 0 | 0.00 |
| hook-on | 50 | 17/50 | 0.59 | 0.00 | 68% | −36% | 62 | 274 | 0 | 0.00 |
| hook-strict | 50 | 24/50 | 0.34 | 0.00 | 76% | −64% | 60 | 385 | 2 | 0.00 |

## Method

Each prompt ran once per arm with `claude -p --setting-sources project --tools Skill`, so no user settings, hooks, or other plugins were loaded. `skill` and `style` load the simple-english plugin with `--plugin-dir`. `style` appends the plugin's output style text as system prompt. `hook-on` and `hook-strict` also load this plugin with `--plugin-dir` and set `STE_MODE`. `Skill fired` counts replies where Claude invoked the simple-english skill. `Strict blocks` counts replies the Stop hook sent back for a rewrite. Raw runs: `results/raw/`.

Models: `claude-fable-5` (claude), `claude-haiku-4-5-20251001` (claude), `claude-opus-5` (claude), `claude-sonnet-5` (claude), `gpt-5.4-mini` (codex), `gpt-5.6-sol` (codex). The `skill` arm against the two hook arms is the comparison that matters. The only thing this plugin changes is how often the rules apply. The `baseline` and `style` arms are a reference and ran for `claude-sonnet-5` (claude) only. `Output tokens per reply` is the mean of `output_tokens` from the CLI usage report. In `hook-strict` it includes the rewrite. Raw record names follow `<harness>__<model>__<arm>__<id>.json`. A `codex` harness writes the same schema from Codex CLI with `evals/codex_bench.py`.
