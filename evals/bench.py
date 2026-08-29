#!/usr/bin/env python3
"""Benchmark: does the hook make Claude Code follow STE on every reply?

Runs each prompt through `claude -p` under up to five arms, for one or more
models, then scores every reply with the simple-english plugin's own linter
(ste_lint.py).

Arms
  skill        simple-english plugin loaded (the skill can trigger)   [default]
  hook-on      simple-english plugin + this plugin, STE_MODE=on       [default]
  hook-strict  same, STE_MODE=strict (the Stop hook lints and can block once) [default]
  baseline     no plugin, no hook                                     (--arms)
  style        simple-english plugin + its output style text as system prompt (--arms)

The skill arm against the hook arms is the comparison that matters. The only
thing this plugin changes is how often the rules apply, so baseline and style
are kept as a reference and are off by default.

Usage
  python3 evals/bench.py --smoke                       # 2 prompts x 3 arms
  python3 evals/bench.py                               # all prompts x 3 arms, claude-sonnet-5
  python3 evals/bench.py --model claude-opus-5,claude-haiku-4-5-20251001 --jobs 5
  python3 evals/bench.py --arms baseline,style --model claude-sonnet-5
  python3 evals/bench.py --report                      # rebuild RESULTS.md from raw/

Every raw run is saved to evals/results/raw/<harness>__<model>__<arm>__<id>.json
with harness=claude. Other harness runners (for example evals/codex_bench.py)
write the same schema with their own harness name, and --report reads them all.
Runs that already exist with exit 0 are skipped, so the benchmark can resume.
"""
import argparse, glob, json, os, statistics, subprocess, sys, tempfile, time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
RAW = HERE / "results" / "raw"
CLAUDE_DIR = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude"))
HARNESS = "claude"
ARMS = ["baseline", "skill", "style", "hook-on", "hook-strict"]
DEFAULT_ARMS = ["skill", "hook-on", "hook-strict"]
HEADLINE_ARMS = ["skill", "hook-on", "hook-strict"]
DEFAULT_MODEL = "claude-sonnet-5"


def find_plugin_file(rel):
    for pat in [CLAUDE_DIR / "plugins/cache/simple-english/simple-english/*" / rel,
                CLAUDE_DIR / "plugins/marketplaces/simple-english" / rel]:
        hits = sorted(glob.glob(str(pat)))
        if hits:
            return Path(hits[-1])
    sys.exit(f"simple-english plugin file not found: {rel}. Install the plugin first.")


PLUGIN_DIR = find_plugin_file("output-styles/simple-english.md").parent.parent
LINT = find_plugin_file("evals/ste_lint.py")
sys.path.insert(0, str(LINT.parent))
import ste_lint  # noqa: E402


def style_text():
    lines = (PLUGIN_DIR / "output-styles/simple-english.md").read_text().split("\n")
    if lines and lines[0] == "---":
        lines = lines[lines.index("---", 1) + 1:]
    return "\n".join(lines).strip()


def raw_path(harness, model, arm, pid):
    return RAW / f"{harness}__{model.replace('/', '-')}__{arm}__{pid}.json"


def run_one(arm, item, model, workdir, max_turns, timeout):
    out = raw_path(HARNESS, model, arm, item["id"])
    if out.exists():
        cached = json.loads(out.read_text())
        if cached.get("exit") == 0 and cached.get("text"):
            return cached
    env = dict(os.environ)
    env.pop("STE_MODE", None)
    cmd = ["claude", "-p", "--output-format", "stream-json", "--verbose",
           "--setting-sources", "project", "--no-session-persistence",
           "--max-turns", str(max_turns), "--model", model, "--tools", "Skill"]
    if arm != "baseline":
        cmd += ["--plugin-dir", str(PLUGIN_DIR)]
    if arm == "style":
        cmd += ["--append-system-prompt", style_text()]
    if arm.startswith("hook"):
        cmd += ["--plugin-dir", str(REPO)]
        env["STE_MODE"] = "on" if arm == "hook-on" else "strict"
        env["STE_LOG"] = str(workdir / f"{model}__{arm}__{item['id']}.blocks")
    t0 = time.time()
    proc = subprocess.run(cmd, input=item["prompt"], cwd=workdir, env=env,
                          capture_output=True, text=True, timeout=timeout)
    events = []
    for line in proc.stdout.splitlines():
        line = line.strip()
        if line.startswith("{"):
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    result = next((e for e in events if e.get("type") == "result"), {})
    init = next((e for e in events if e.get("type") == "system" and e.get("subtype") == "init"), {})
    skill_used = False
    assistant_texts = 0
    texts = []
    for e in events:
        if e.get("type") != "assistant":
            continue
        for block in e.get("message", {}).get("content", []):
            if block.get("type") == "tool_use" and block.get("name") == "Skill" \
                    and "simple-english" in json.dumps(block.get("input", {})):
                skill_used = True
            if block.get("type") == "text" and block.get("text", "").strip():
                assistant_texts += 1
                texts.append(block["text"])
    text = result.get("result", "") or ""
    blocks_file = Path(env.get("STE_LOG", "/nonexistent"))
    blocked = blocks_file.read_text().count("block") if blocks_file.exists() else 0
    lint = ste_lint.lint(text, "procedural" if item["cat"] in ("runbook",) else "descriptive")
    rec = {
        "harness": HARNESS,
        "arm": arm, "id": item["id"], "cat": item["cat"], "model": model,
        "exit": proc.returncode, "seconds": round(time.time() - t0, 1),
        "skill_available": any("simple-english" in s for s in init.get("slash_commands", [])),
        "skill_used": skill_used, "assistant_text_messages": assistant_texts,
        "strict_blocks": blocked,
        "num_turns": result.get("num_turns"), "cost_usd": result.get("total_cost_usd"),
        "usage": result.get("usage"), "lint": lint, "text": text,
        "texts": texts,  # every assistant text block; in strict mode texts[0] is the reply before the rewrite
        "stderr_tail": proc.stderr[-800:],
    }
    out.write_text(json.dumps(rec, indent=2))
    return rec


# ---------------------------------------------------------------- report

def _out_tokens(r):
    return ((r.get("usage") or {}).get("output_tokens")) or 0


def arm_stats(rs):
    v = [r["lint"]["violations_per_100w"] for r in rs]
    return {
        "n": len(rs),
        "skill_used": sum(1 for r in rs if r.get("skill_used")),
        "mean_v100": statistics.mean(v), "median_v100": statistics.median(v),
        "zero_pct": 100 * sum(1 for r in rs if r["lint"]["violations_total"] == 0) / len(rs),
        "mean_words": statistics.mean(r["lint"]["words"] for r in rs),
        "mean_out_tokens": statistics.mean(_out_tokens(r) for r in rs),
        "blocks": sum(r.get("strict_blocks") or 0 for r in rs),
        "cost": sum(r.get("cost_usd") or 0 for r in rs),
    }


def reduction(ref, x):
    """Percent reduction of x against ref, or None when ref is 0."""
    return None if not ref else 100 * (1 - x / ref)


def fmt_reduction(pct, signed=False):
    if pct is None:
        return "—"
    if signed:
        return f"−{pct:.0f}%" if pct >= 0 else f"+{-pct:.0f}%"
    return f"{pct:.0f}%"


def model_label(harness, model):
    return f"`{model}` ({harness})"


def report(records):
    records = [r for r in records if r.get("text") and r.get("exit") == 0]
    groups = {}  # (harness, model) -> arm -> [records]
    for r in records:
        key = (r.get("harness", HARNESS), r["model"])
        groups.setdefault(key, {}).setdefault(r["arm"], []).append(r)
    # Claude harness first, then the rest by name; inside a harness, by model name.
    keys = sorted(groups, key=lambda k: (k[0] != HARNESS, k[0], k[1]))
    prompt_ids = sorted(set(r["id"] for r in records))

    lines = ["# Results", "",
             f"Scorer: the simple-english plugin's `ste_lint.py`. It is a regex pass. It undercounts, and the numbers compare arms only.",
             f"Prompts: {len(prompt_ids)}. Models: " + ", ".join(model_label(*k) for k in keys) + ".", ""]

    # 2. Cross-model summary
    lines += ["## Cross-model summary", "",
              "| Model | n prompts | skill alone (v/100w) | hook on (v/100w) | hook strict (v/100w) | reduction (strict vs skill) |",
              "|---|---:|---:|---:|---:|---:|"]
    for k in keys:
        by_arm = groups[k]
        st = {arm: arm_stats(by_arm[arm]) for arm in HEADLINE_ARMS if by_arm.get(arm)}
        n = len(set(r["id"] for arm in HEADLINE_ARMS for r in by_arm.get(arm, [])))
        cell = lambda arm: f"{st[arm]['mean_v100']:.2f}" if arm in st else "—"  # noqa: E731
        red = fmt_reduction(reduction(st["skill"]["mean_v100"], st["hook-strict"]["mean_v100"])) \
            if "skill" in st and "hook-strict" in st else "—"
        lines.append(f"| {model_label(*k)} | {n} | {cell('skill')} | {cell('hook-on')} | {cell('hook-strict')} | {red} |")
    lines.append("")

    # Per model: every arm that ran, all columns. The reduction column compares
    # against the skill arm, because the skill alone is what this plugin replaces.
    lines += ["## Per model", "",
              "Every arm that ran for the model, with all columns. "
              "The reduction column compares against the `skill` arm.", ""]
    for k in keys:
        by_arm = groups[k]
        present = [arm for arm in ARMS if by_arm.get(arm)]
        if not present:
            continue
        ref = arm_stats(by_arm["skill"])["mean_v100"] if by_arm.get("skill") else None
        lines += [f"### {model_label(*k)}", "",
                  "| Arm | n | Skill fired | Violations / 100 words (mean) | median | Replies with 0 violations | Reduction vs skill | Mean words | Mean output tokens | Strict blocks | Cost USD |",
                  "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"]
        for arm in present:
            st = arm_stats(by_arm[arm])
            red = fmt_reduction(reduction(ref, st["mean_v100"]), signed=True) if ref is not None and arm != "skill" else "—"
            lines.append(f"| {arm} | {st['n']} | {st['skill_used']}/{st['n']} | {st['mean_v100']:.2f} | {st['median_v100']:.2f} | "
                         f"{st['zero_pct']:.0f}% | {red} | {st['mean_words']:.0f} | "
                         f"{st['mean_out_tokens']:.0f} | {st['blocks']} | {st['cost']:.2f} |")
        lines.append("")

    full = [k for k in keys if groups[k].get("baseline") and groups[k].get("style")]
    # 4. Method
    lines += ["## Method", "",
              "Each prompt ran once per arm with `claude -p --setting-sources project --tools Skill`, so no user settings, hooks, or other plugins were loaded. "
              "`skill` and `style` load the simple-english plugin with `--plugin-dir`. `style` appends the plugin's output style text as system prompt. "
              "`hook-on` and `hook-strict` also load this plugin with `--plugin-dir` and set `STE_MODE`. "
              "`Skill fired` counts replies where Claude invoked the simple-english skill. "
              "`Strict blocks` counts replies the Stop hook sent back for a rewrite. Raw runs: `results/raw/`.", "",
              "Models: " + ", ".join(model_label(*k) for k in keys) + ". "
              "The `skill` arm against the two hook arms is the comparison that matters. "
              "The only thing this plugin changes is how often the rules apply. "
              "The `baseline` and `style` arms are a reference and ran for "
              + (", ".join(model_label(*k) for k in full) if full else "no model") + " only. "
              "`Output tokens per reply` is the mean of `output_tokens` from the CLI usage report. In `hook-strict` it includes the rewrite. "
              "Raw record names follow `<harness>__<model>__<arm>__<id>.json`. "
              "A `codex` harness writes the same schema from Codex CLI with `evals/codex_bench.py`.", ""]
    (HERE / "results" / "RESULTS.md").write_text("\n".join(lines))
    print("\n".join(lines[:10 + len(keys)]))


def load_raw():
    return [json.loads(Path(f).read_text()) for f in sorted(RAW.glob("*.json"))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--arms", default=",".join(DEFAULT_ARMS), help=f"comma list from {','.join(ARMS)}")
    ap.add_argument("--n", type=int, default=0, help="first N prompts (0 = all)")
    ap.add_argument("--smoke", action="store_true", help="2 prompts")
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--model", default=DEFAULT_MODEL, help="comma-separated list of model ids")
    ap.add_argument("--max-turns", type=int, default=6)
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--report", action="store_true", help="only rebuild RESULTS.md")
    a = ap.parse_args()
    RAW.mkdir(parents=True, exist_ok=True)
    if a.report:
        report(load_raw())
        return
    prompts = json.loads((HERE / "prompts.json").read_text())
    if a.smoke:
        prompts = prompts[:2]
    elif a.n:
        prompts = prompts[:a.n]
    arms = [x for x in a.arms.split(",") if x in ARMS]
    models = [m.strip() for m in a.model.split(",") if m.strip()]
    workdir = Path(tempfile.mkdtemp(prefix="ste-bench-"))
    for model in models:
        jobs = [(arm, p) for p in prompts for arm in arms]
        print(f"{len(jobs)} runs, {a.jobs} parallel, model {model}, workdir {workdir}", flush=True)
        failed = 0
        with ThreadPoolExecutor(max_workers=a.jobs) as ex:
            futs = {ex.submit(run_one, arm, p, model, workdir, a.max_turns, a.timeout): (arm, p["id"]) for arm, p in jobs}
            for f in as_completed(futs):
                arm, pid = futs[f]
                try:
                    r = f.result()
                    flag = "SKILL" if r["skill_used"] else "     "
                    print(f"  {model} {arm:11s} {pid:12s} {flag} v/100w={r['lint']['violations_per_100w']:5.2f} "
                          f"words={r['lint']['words']:4d} blocks={r['strict_blocks']} exit={r['exit']}", flush=True)
                    if r["exit"] != 0 or not r["text"]:
                        failed += 1
                        print(f"    stderr: {r['stderr_tail'][-200:]!r}", flush=True)
                except Exception as e:  # noqa: BLE001
                    failed += 1
                    print(f"  {model} {arm:11s} {pid:12s} FAILED: {e}", flush=True)
        print(f"model {model} done, {failed} failed runs (re-run the same command to retry them)", flush=True)
    report(load_raw())


if __name__ == "__main__":
    main()
