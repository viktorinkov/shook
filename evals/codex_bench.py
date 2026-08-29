#!/usr/bin/env python3
"""Benchmark: does the hook make Codex CLI follow STE on every reply?

Runs each prompt from prompts.json through `codex exec` under three arms, then
scores every reply with the simple-english plugin's own linter (ste_lint.py).
The raw records use the same schema as bench.py, plus a "harness" field, so
`bench.py --report` can read both sets.

Arms (they mirror the Claude arms; Codex has no output-style arm)
  skill        simple-english SKILL.md installed as a Codex plugin skill, no hooks
  hook-on      skill arm + this plugin's hooks, STE_MODE=on
  hook-strict  same, STE_MODE=strict (the Stop hook lints and can block once)

Codex plugin state is global (per CODEX_HOME), not per-invocation. The script
therefore builds a scratch CODEX_HOME (auth.json is copied from ~/.codex and
deleted at the end), installs the plugins there from a scratch local
marketplace, and runs the arms sequentially: configure, run all prompts,
reconfigure. The user's ~/.codex is never touched.

Usage
  python3 evals/codex_bench.py --smoke                  # 2 prompts x 3 arms
  python3 evals/codex_bench.py                          # all prompts x 3 arms x models
  python3 evals/codex_bench.py --models gpt-5.6-sol --arms skill --n 10 --jobs 3

Every raw run is saved to evals/results/raw/codex__<model>__<arm>__<id>.json.
Runs that already exist are skipped, so the benchmark can resume.
Records with exit != 0 or an empty reply are deleted at the end, so a re-run
picks them up.
"""
import argparse, glob, json, os, shutil, statistics, subprocess, sys, tempfile, threading, time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
RAW = HERE / "results" / "raw"
CLAUDE_DIR = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude"))
CODEX_REAL = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
ARMS = ["skill", "hook-on", "hook-strict"]
MARKET = "ste-bench"
HOOK_PLUGIN = f"simple-english-hook@{MARKET}"


def find_plugin_file(rel):
    if os.environ.get("STE_PLUGIN_DIR"):
        p = Path(os.environ["STE_PLUGIN_DIR"]).expanduser() / rel
        if p.exists():
            return p
    for pat in [CLAUDE_DIR / "plugins/cache/simple-english/simple-english/*" / rel,
                CLAUDE_DIR / "plugins/marketplaces/simple-english" / rel]:
        hits = sorted(glob.glob(str(pat)))
        if hits:
            return Path(hits[-1])
    sys.exit(f"simple-english plugin file not found: {rel}. Install the plugin first "
             "or set STE_PLUGIN_DIR to a clone of AminBlg/SimpleEnglish.")


PLUGIN_DIR = find_plugin_file("skills/simple-english/SKILL.md").parent.parent.parent
LINT = find_plugin_file("evals/ste_lint.py")
sys.path.insert(0, str(LINT.parent))
import ste_lint  # noqa: E402


def codex(home, *args, check=True):
    env = dict(os.environ)
    env["CODEX_HOME"] = str(home)
    proc = subprocess.run(["codex", *args], env=env, capture_output=True, text=True)
    if check and proc.returncode != 0:
        sys.exit(f"codex {' '.join(args)} failed:\n{proc.stdout}\n{proc.stderr}")
    return proc


def setup_home(base):
    """Scratch CODEX_HOME + a scratch local marketplace with both plugins."""
    home = base / "codex-home"
    home.mkdir(parents=True)
    shutil.copy2(CODEX_REAL / "auth.json", home / "auth.json")
    (home / "auth.json").chmod(0o600)
    if (CODEX_REAL / "models_cache.json").exists():
        shutil.copy2(CODEX_REAL / "models_cache.json", home / "models_cache.json")
    (home / "config.toml").write_text("[features]\nhooks = true\n")

    market = base / "market"
    (market / ".agents/plugins").mkdir(parents=True)
    ste = market / "simple-english"
    (ste / ".codex-plugin").mkdir(parents=True)
    (ste / "skills").mkdir()
    shutil.copytree(PLUGIN_DIR / "skills/simple-english", ste / "skills/simple-english")
    (ste / ".codex-plugin/plugin.json").write_text(json.dumps({
        "name": "simple-english", "version": "1.3.0",
        "description": "ASD-STE100 Simplified Technical English skill (AminBlg/SimpleEnglish).",
        "skills": "./skills/"}, indent=2))
    (market / "simple-english-hook").symlink_to(REPO)
    (market / ".agents/plugins/marketplace.json").write_text(json.dumps({
        "name": MARKET,
        "plugins": [
            {"name": "simple-english", "source": {"source": "local", "path": "./simple-english"},
             "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"}},
            {"name": "simple-english-hook", "source": {"source": "local", "path": "./simple-english-hook"},
             "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"}},
        ]}, indent=2))
    codex(home, "plugin", "marketplace", "add", str(market))
    codex(home, "plugin", "add", f"simple-english@{MARKET}")
    return home


def set_arm(home, arm):
    """The skill arm must not have the hook plugin; the hook arms need it."""
    listed = codex(home, "plugin", "list", "--json").stdout
    have = any(p.get("pluginId") == HOOK_PLUGIN for p in json.loads(listed).get("installed", []))
    if arm == "skill" and have:
        codex(home, "plugin", "remove", HOOK_PLUGIN)
    elif arm != "skill" and not have:
        codex(home, "plugin", "add", HOOK_PLUGIN)


FAIL_LOCK = threading.Lock()
FAILS = {"consecutive": 0, "stop": False}


def note_result(ok, limit):
    with FAIL_LOCK:
        FAILS["consecutive"] = 0 if ok else FAILS["consecutive"] + 1
        if FAILS["consecutive"] >= limit:
            FAILS["stop"] = True


def run_one(arm, item, model, home, workdir, blockdir, timeout, effort):
    out = RAW / f"codex__{model}__{arm}__{item['id']}.json"
    if out.exists():
        cached = json.loads(out.read_text())
        if cached.get("exit") == 0 and cached.get("text"):
            return cached
    if FAILS["stop"]:
        raise RuntimeError("stopped after repeated failures")
    env = {k: v for k, v in os.environ.items() if not k.startswith("STE_")}
    env["CODEX_HOME"] = str(home)
    cmd = ["codex", "exec", "--json", "-s", "read-only", "--skip-git-repo-check",
           "--ephemeral", "--model", model, "-c", f'model_reasoning_effort="{effort}"']
    blocks_file = blockdir / f"{model}__{arm}__{item['id']}.blocks"
    if arm.startswith("hook"):
        cmd += ["--dangerously-bypass-hook-trust"]
        env["STE_MODE"] = "on" if arm == "hook-on" else "strict"
        env["STE_PLUGIN_DIR"] = str(PLUGIN_DIR)
        env["STE_LOG"] = str(blocks_file)
        blocks_file.unlink(missing_ok=True)
    t0 = time.time()
    try:
        proc = subprocess.run(cmd, input=item["prompt"], cwd=workdir, env=env,
                              capture_output=True, text=True, timeout=timeout)
        rc, stdout, stderr = proc.returncode, proc.stdout, proc.stderr
    except subprocess.TimeoutExpired as e:
        rc, stdout, stderr = -1, (e.stdout or ""), f"timeout after {timeout}s\n{e.stderr or ''}"
    events = []
    for line in stdout.splitlines():
        line = line.strip()
        if line.startswith("{"):
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    texts, skill_used, usage = [], False, {}
    for e in events:
        item_obj = e.get("item") or {}
        if e.get("type") == "item.completed" and item_obj.get("type") == "agent_message":
            if item_obj.get("text", "").strip():
                texts.append(item_obj["text"])
        elif item_obj.get("type") not in ("agent_message", "reasoning", None) \
                and "skills/simple-english" in json.dumps(item_obj):
            skill_used = True  # Codex loads a skill by reading its SKILL.md / references
        if e.get("type") == "turn.completed":
            for k, v in (e.get("usage") or {}).items():
                if isinstance(v, (int, float)):
                    usage[k] = usage.get(k, 0) + v
    num_turns = sum(1 for e in events if e.get("type") == "turn.completed")
    text = texts[-1] if texts else ""
    blocked = blocks_file.read_text().count("block") if blocks_file.exists() else 0
    lint = ste_lint.lint(text, "procedural" if item["cat"] in ("runbook",) else "descriptive")
    skill_avail = bool(glob.glob(str(home / f"plugins/cache/{MARKET}/simple-english/*/skills/simple-english/SKILL.md")))
    rec = {
        "harness": "codex", "arm": arm, "id": item["id"], "cat": item["cat"], "model": model,
        "exit": rc, "seconds": round(time.time() - t0, 1),
        "skill_available": skill_avail, "skill_used": skill_used,
        "assistant_text_messages": len(texts),
        "strict_blocks": blocked, "num_turns": num_turns,
        "cost_usd": None,  # ChatGPT-plan auth reports no cost
        "usage": usage or None, "lint": lint, "text": text,
        "texts": texts,  # every agent message; after a strict block texts[0] is the reply before the rewrite
        "stderr_tail": stderr[-800:],
    }
    out.write_text(json.dumps(rec, indent=2))
    note_result(rc == 0 and bool(text), limit=6)
    if FAILS["stop"]:
        raise RuntimeError(f"aborting: {FAILS['consecutive']} consecutive failures (last: {stderr[-200:]})")
    return rec


def summary(records):
    print("\narm          model          n   skill  v/100w  blocks")
    key = lambda r: (r["arm"], r["model"])
    for k in sorted(set(key(r) for r in records)):
        rs = [r for r in records if key(r) == k and r["text"]]
        if not rs:
            continue
        v = statistics.mean(r["lint"]["violations_per_100w"] for r in rs)
        print(f"{k[0]:12s} {k[1]:14s} {len(rs):3d}  {sum(1 for r in rs if r['skill_used']):3d}   {v:6.2f}  "
              f"{sum(r['strict_blocks'] for r in rs):3d}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", default="gpt-5.6-sol,gpt-5.4-mini")
    ap.add_argument("--arms", default=",".join(ARMS))
    ap.add_argument("--n", type=int, default=0, help="first N prompts (0 = all)")
    ap.add_argument("--smoke", action="store_true", help="2 prompts")
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--effort", default="low", help="model_reasoning_effort")
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--keep-home", action="store_true", help="keep the scratch CODEX_HOME")
    a = ap.parse_args()
    RAW.mkdir(parents=True, exist_ok=True)
    prompts = json.loads((HERE / "prompts.json").read_text())
    if a.smoke:
        prompts = prompts[:2]
    elif a.n:
        prompts = prompts[:a.n]
    arms = [x for x in a.arms.split(",") if x in ARMS]
    models = [m for m in a.models.split(",") if m]

    base = Path(tempfile.mkdtemp(prefix="ste-codex-bench-"))
    workdir = base / "work"
    blockdir = base / "blocks"
    workdir.mkdir()
    blockdir.mkdir()
    home = setup_home(base)
    print(f"{len(prompts) * len(arms) * len(models)} runs, {a.jobs} parallel, "
          f"models {models}, scratch home {home}", flush=True)
    records = []
    try:
        for arm in arms:  # arms are sequential: plugin state is global per CODEX_HOME
            set_arm(home, arm)
            for model in models:
                with ThreadPoolExecutor(max_workers=a.jobs) as ex:
                    futs = {ex.submit(run_one, arm, p, model, home, workdir, blockdir,
                                      a.timeout, a.effort): p["id"] for p in prompts}
                    for f in as_completed(futs):
                        pid = futs[f]
                        try:
                            r = f.result()
                            flag = "SKILL" if r["skill_used"] else "     "
                            print(f"  {arm:11s} {model:14s} {pid:12s} {flag} "
                                  f"v/100w={r['lint']['violations_per_100w']:5.2f} "
                                  f"words={r['lint']['words']:4d} blocks={r['strict_blocks']} exit={r['exit']}",
                                  flush=True)
                            records.append(r)
                        except Exception as e:  # noqa: BLE001
                            print(f"  {arm:11s} {model:14s} {pid:12s} FAILED: {e}", flush=True)
                if FAILS["stop"]:
                    print("stopping: repeated failures", flush=True)
                    break
            if FAILS["stop"]:
                break
    finally:
        bad = 0
        for f in RAW.glob("codex__*.json"):
            r = json.loads(f.read_text())
            if r.get("exit") != 0 or not r.get("text"):
                f.unlink()
                bad += 1
        if bad:
            print(f"deleted {bad} failed records; re-run to retry them", flush=True)
        if a.keep_home:
            print(f"kept scratch home: {base}", flush=True)
        else:
            shutil.rmtree(base, ignore_errors=True)  # removes the auth.json copy too
    summary(records)


if __name__ == "__main__":
    main()
