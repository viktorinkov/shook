#!/usr/bin/env python3
"""Benchmark: does the hook make Claude Code follow STE on every reply?

Runs each prompt through `claude -p` under five arms, then scores every reply
with the simple-english plugin's own linter (evals/ste_lint.py).

Arms
  baseline     no plugin, no hook
  skill        simple-english plugin loaded (the skill can trigger)
  style        simple-english plugin + its output style text as system prompt
  hook-on      simple-english plugin + this plugin, STE_MODE=on
  hook-strict  same, STE_MODE=strict (the Stop hook lints and can block once)

Usage
  python3 evals/bench.py --smoke              # 2 prompts x 5 arms
  python3 evals/bench.py                      # all prompts x 5 arms
  python3 evals/bench.py --arms baseline,hook-on --n 10 --jobs 4 --model claude-sonnet-5
  python3 evals/bench.py --report             # rebuild RESULTS.md from raw/

Every raw run is saved to evals/results/raw/<arm>__<id>.json.
Runs that already exist are skipped, so the benchmark can resume.
"""
import argparse, glob, json, os, statistics, subprocess, sys, tempfile, time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
RAW = HERE / "results" / "raw"
CLAUDE_DIR = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude"))
ARMS = ["baseline", "skill", "style", "hook-on", "hook-strict"]


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


def run_one(arm, item, model, workdir, max_turns, timeout):
    out = RAW / f"{arm}__{item['id']}.json"
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
        env["STE_LOG"] = str(workdir / f"{arm}__{item['id']}.blocks")
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


def report(records):
    by_arm = {}
    for r in records:
        by_arm.setdefault(r["arm"], []).append(r)
    rows, base = [], None
    for arm in ARMS:
        rs = [r for r in by_arm.get(arm, []) if r["text"]]
        if not rs:
            continue
        v = [r["lint"]["violations_per_100w"] for r in rs]
        zero = sum(1 for r in rs if r["lint"]["violations_total"] == 0)
        words = [r["lint"]["words"] for r in rs]
        outtok = [(r["usage"] or {}).get("output_tokens", 0) for r in rs]
        row = {
            "arm": arm, "n": len(rs),
            "skill_used": sum(1 for r in rs if r["skill_used"]),
            "mean_v100": statistics.mean(v), "median_v100": statistics.median(v),
            "zero_pct": 100 * zero / len(rs),
            "mean_words": statistics.mean(words), "mean_out_tokens": statistics.mean(outtok),
            "blocks": sum(r["strict_blocks"] for r in rs),
            "cost": sum(r["cost_usd"] or 0 for r in rs),
        }
        if arm == "baseline":
            base = row["mean_v100"]
        row["reduction"] = (100 * (1 - row["mean_v100"] / base)) if base else None
        rows.append(row)
    lines = ["# Results", "",
             f"Model: `{records[0]['model']}`. Prompts: {len(set(r['id'] for r in records))}. "
             f"Scorer: the simple-english plugin's `ste_lint.py` (regex pass, undercounts, comparable between arms only).", "",
             "| Arm | n | Skill fired | Violations / 100 words (mean) | median | Replies with 0 violations | Reduction vs baseline | Mean words | Mean output tokens | Strict blocks | Cost USD |",
             "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for r in rows:
        red = "—" if r["reduction"] is None else f"{r['reduction']:.0f}%"
        lines.append(f"| {r['arm']} | {r['n']} | {r['skill_used']}/{r['n']} | {r['mean_v100']:.2f} | {r['median_v100']:.2f} | "
                     f"{r['zero_pct']:.0f}% | {red} | {r['mean_words']:.0f} | {r['mean_out_tokens']:.0f} | {r['blocks']} | {r['cost']:.2f} |")
    lines += ["", "## Per category (mean violations / 100 words)", ""]
    cats = sorted(set(r["cat"] for r in records))
    lines.append("| Category | " + " | ".join(r["arm"] for r in rows) + " |")
    lines.append("|---|" + "---:|" * len(rows))
    for c in cats:
        cells = []
        for r in rows:
            rs = [x for x in by_arm[r["arm"]] if x["cat"] == c and x["text"]]
            cells.append(f"{statistics.mean(x['lint']['violations_per_100w'] for x in rs):.2f}" if rs else "—")
        lines.append(f"| {c} | " + " | ".join(cells) + " |")
    lines += ["", "## Method", "",
              "Each prompt ran once per arm with `claude -p --setting-sources project --tools Skill`, so no user settings, hooks, or other plugins were loaded. "
              "`skill` and `style` load the simple-english plugin with `--plugin-dir`. `style` appends the plugin's output style text as system prompt. "
              "`hook-on` and `hook-strict` also load this plugin with `--plugin-dir` and set `STE_MODE`. "
              "`Skill fired` counts replies where Claude invoked the simple-english skill. "
              "`Strict blocks` counts replies the Stop hook sent back for a rewrite. Raw runs: `results/raw/`.", ""]
    (HERE / "results" / "RESULTS.md").write_text("\n".join(lines))
    print("\n".join(lines[:4 + len(rows)]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--arms", default=",".join(ARMS))
    ap.add_argument("--n", type=int, default=0, help="first N prompts (0 = all)")
    ap.add_argument("--smoke", action="store_true", help="2 prompts")
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--model", default="claude-sonnet-5")
    ap.add_argument("--max-turns", type=int, default=6)
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--report", action="store_true", help="only rebuild RESULTS.md")
    a = ap.parse_args()
    RAW.mkdir(parents=True, exist_ok=True)
    if a.report:
        report([json.loads(Path(f).read_text()) for f in sorted(RAW.glob("*.json"))])
        return
    prompts = json.loads((HERE / "prompts.json").read_text())
    if a.smoke:
        prompts = prompts[:2]
    elif a.n:
        prompts = prompts[:a.n]
    arms = [x for x in a.arms.split(",") if x in ARMS]
    workdir = Path(tempfile.mkdtemp(prefix="ste-bench-"))
    jobs = [(arm, p) for p in prompts for arm in arms]
    print(f"{len(jobs)} runs, {a.jobs} parallel, model {a.model}, workdir {workdir}", flush=True)
    records = []
    with ThreadPoolExecutor(max_workers=a.jobs) as ex:
        futs = {ex.submit(run_one, arm, p, a.model, workdir, a.max_turns, a.timeout): (arm, p["id"]) for arm, p in jobs}
        for f in as_completed(futs):
            arm, pid = futs[f]
            try:
                r = f.result()
                flag = "SKILL" if r["skill_used"] else "     "
                print(f"  {arm:11s} {pid:12s} {flag} v/100w={r['lint']['violations_per_100w']:5.2f} words={r['lint']['words']:4d} blocks={r['strict_blocks']} exit={r['exit']}", flush=True)
                records.append(r)
            except Exception as e:  # noqa: BLE001
                print(f"  {arm:11s} {pid:12s} FAILED: {e}", flush=True)
    report([json.loads(Path(f).read_text()) for f in sorted(RAW.glob("*.json"))])


if __name__ == "__main__":
    main()
