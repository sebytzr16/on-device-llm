#!/usr/bin/env python3
"""Turn research_eval_test logs into a Markdown table.

    python scripts/summarize-eval.py artifacts/eval-qwen.log artifacts/eval-gemma.log
"""
import json
import re
import sys


def load(path):
    rows, summary = [], None
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.search(r"EVAL: (\{.*\})", line)
        if m:
            rows.append(json.loads(m.group(1)))
        m = re.search(r"EVAL_SUMMARY: (\{.*\})", line)
        if m:
            summary = json.loads(m.group(1))
    return rows, summary


def main(paths):
    for path in paths:
        rows, summary = load(path)
        if not rows:
            print(f"{path}: no EVAL lines")
            continue
        s = summary or {}
        n = s.get("questions", len(rows))
        checked = sum(r.get("correct") is not None for r in rows)
        backend = (rows[0].get("backend") or "")
        print(f"### {rows[0]['family']} · mode {rows[0]['mode']} · {backend} · {path}")
        print()
        stage_keys = ["judgeMs", "planMs", "searchMs", "readMs", "budgetMs", "generateMs"]
        stage_med = {}
        for k in stage_keys:
            vals = sorted((r.get("stages") or {}).get(k, 0) for r in rows)
            stage_med[k] = vals[len(vals) // 2] / 1000 if vals else 0
        print(
            f"retrieved {s.get('retrieved', 0)}/{n} · read {s.get('read', 0)}/{n} · cited {s.get('cited', 0)}/{n} · "
            f"citation checks {s.get('grounded', 0)}/{n} · **gold rules passed {s.get('correct', 0)}/{checked}** · needs review {n - checked} · errors {s.get('errors', 0)} · "
            f"median {sorted(r['seconds'] for r in rows)[len(rows) // 2]:.1f} s"
        )
        print()
        print("median stages: " + " · ".join(f"{k[:-2]} {v:.1f}s" for k, v in stage_med.items() if v) +
              f" · prompt tokens {sorted(r.get('promptTokens') or 0 for r in rows)[len(rows) // 2]}")
        print()
        # Per-kind scoreboard (question set v2): what each overhaul phase moves.
        kinds = {}
        for r in rows:
            k = kinds.setdefault(r.get("kind", "fact"), {"n": 0, "checked": 0, "correct": 0, "pages": [], "seconds": [], "tokens": []})
            k["n"] += 1
            k["correct"] += 1 if r["correct"] else 0
            k["checked"] += 1 if r.get("correct") is not None else 0
            k["pages"].append(r.get("pages", 0))
            k["seconds"].append(r["seconds"])
            k["tokens"].append(r.get("promptTokens") or 0)
        median = lambda xs: sorted(xs)[len(xs) // 2] if xs else 0
        print("| kind | gold rules passed / checked | median pages | median s | median prompt tokens |")
        print("|---|---|---|---|---|")
        for name, k in sorted(kinds.items()):
            print(f"| {name} | {k['correct']}/{k['checked']} | {median(k['pages'])} | {median(k['seconds']):.0f} | {median(k['tokens'])} |")
        print(f"| all | {s.get('correct', 0)}/{checked} | {median([r.get('pages', 0) for r in rows])} | "
              f"{median([r['seconds'] for r in rows]):.0f} | {median([r.get('promptTokens') or 0 for r in rows])} |")
        print()
        # D1 benchmark (eval/d1_benchmark.json): did each question search when
        # it should, and how much web did it use.
        if any("set" in r for r in rows):
            if s.get("frozen"):
                print(f"frozen web: {s['frozen']} · calls {s.get('webCalls', {})} · misses {len(s.get('frozenMisses') or [])}")
                print()
            print("| set | n | gold rules passed / checked | searched | router right / scored | median s | web calls |")
            print("|---|---|---|---|---|---|---|")
            groups = {}
            for r in rows:
                groups.setdefault(r.get("set", "-"), []).append(r)
            groups["all"] = rows
            for name, rs in groups.items():
                scored = [r for r in rs if r.get("routerOk") is not None]
                calls = sum(sum((r.get("webCalls") or {}).values()) for r in rs)
                print(
                    f"| {name} | {len(rs)} | {sum(1 for r in rs if r.get('correct'))}/{sum(1 for r in rs if r.get('correct') is not None)} | "
                    f"{sum(1 for r in rs if r.get('searched'))} | {sum(1 for r in scored if r['routerOk'])}/{len(scored)} | "
                    f"{median([r['seconds'] for r in rs]):.1f} | {calls} |"
                )
            print()
        print("| id | kind | correct | src | pages | cite | grounded | s | notice / answer |")
        print("|---|---|---|---|---|---|---|---|---|")
        for r in rows:
            mark = "review" if r.get("correct") is None else "yes" if r["correct"] else "NO"
            note = (r.get("grounding") or r.get("notice") or "") or ""
            ans = r["answer"].replace("\n", " ").strip()
            print(
                f"| {r['id']} | {r.get('kind', 'fact')} | {mark} | {r['sources']} | {r.get('pages', 'y' if r['read'] else 0)} | {'y' if r['cited'] else '-'} | "
                f"{'y' if r['grounded'] else '-'} | {r['seconds']:.0f} | {note[:70]}{" | " if note else ""}{ans[:110]} |"
            )
        print()


if __name__ == "__main__":
    main(sys.argv[1:])
