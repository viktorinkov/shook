# Codex CLI benchmark

`codex_bench.py` runs the same 50 prompts from `prompts.json` through OpenAI
Codex CLI. It writes raw records in the same schema as `bench.py`, plus a
`harness` field. File names: `results/raw/codex__<model>__<arm>__<id>.json`.

## Arms

| Arm | Setup |
|---|---|
| `skill` | The simple-english SKILL.md installed as a Codex plugin skill. No hooks. |
| `hook-on` | The skill plus this plugin's hooks, `STE_MODE=on`. |
| `hook-strict` | The same with `STE_MODE=strict`. The Stop hook lints each reply and can block it once. `STE_LOG` counts the blocks. |

Codex has no output-style arm and no clean baseline arm. A Codex baseline
would need a home with no plugins, which is a different comparison than the
Claude baseline. The three arms above mirror the Claude arms of the same name.

## How it isolates the runs

Codex plugin state is global per `CODEX_HOME`, not per invocation. The script
builds a scratch `CODEX_HOME` in a temp directory:

- It copies `auth.json` and `models_cache.json` from `~/.codex`.
- It writes a minimal `config.toml` with `[features] hooks = true`.
- It writes a scratch local marketplace with two plugins: `simple-english`
  (the SKILL.md copied from the installed AminBlg/SimpleEnglish plugin,
  wrapped in a minimal `.codex-plugin/plugin.json`) and `simple-english-hook`
  (a symlink to this repo).
- It installs the plugins with `codex plugin marketplace add` and
  `codex plugin add`, and removes or adds the hook plugin between arms.

The arms run sequentially. Each `codex exec` runs with `--ephemeral`, so no
session files persist. The script deletes the scratch home, with the auth
copy, at the end. The user's `~/.codex` does not change.

## Exact commands

```bash
# all prompts, both models, three arms (300 runs, resumable)
python3 evals/codex_bench.py --models gpt-5.6-sol,gpt-5.4-mini --jobs 3

# quick check: 2 prompts x 3 arms
python3 evals/codex_bench.py --smoke --models gpt-5.6-sol
```

Each run is:

```bash
CODEX_HOME=<scratch> codex exec --json -s read-only --skip-git-repo-check \
  --ephemeral --model <model> -c model_reasoning_effort="low" < prompt
```

The hook arms add `--dangerously-bypass-hook-trust` and the environment
`STE_MODE`, `STE_PLUGIN_DIR` (the installed simple-english plugin directory),
and `STE_LOG` (one block-count file per run).

## Record fields, Codex specifics

- `model`: `gpt-5.6-sol` is the Codex default model. `gpt-5.4-mini` is the
  smallest listed model.
- `skill_used`: true when the event stream shows a read of
  `skills/simple-english` (Codex loads a skill when the model reads its
  SKILL.md or references).
- `num_turns`: `turn.completed` events. A strict block continues the same
  turn, so this is 1 in almost every record. The rewrite shows as a second
  entry in `texts` and in `strict_blocks`.
- `cost_usd`: always null. ChatGPT-plan auth reports no cost.
- `usage`: summed over `turn.completed` events. Keys follow the Codex stream:
  `input_tokens`, `cached_input_tokens`, `cache_write_input_tokens`,
  `output_tokens`, `reasoning_output_tokens`.

Verified with Codex CLI 0.149.0 on macOS.
