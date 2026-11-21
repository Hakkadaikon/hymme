"""Draw the reachable states of a TLA+ spec as a Mermaid chart, with the shortest path to each broken rule.

TLC stops at the first rule that breaks, so the run is repeated with that rule removed until none
breaks. The report names every rule as held, broken (with its path) or not checked.
shortcut: invariants only; a temporal property that breaks is reported without a path. Charts above
MAX_STATES draw only the paths to broken rules.
"""

import hashlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

MESSAGES = {
    "no_spec": "{path} が無い。",
    "no_tlc": "tlc が PATH に無い。hymme の skill-tools を入れてから実行する。",
    "tlc_error": "TLC が判定できずに止まった(spec か cfg の誤り)。出力の末尾:\n{tail}",
    "wrote": "{report} と {chart} を書いた。破れた規則 {broken} 件、検査されなかった規則 {unchecked} 件。",
}

MAX_STATES = 200
KEYWORDS = {"CONSTANT", "CONSTANTS", "INIT", "NEXT", "SPECIFICATION", "INVARIANT", "INVARIANTS", "PROPERTY"}
KEYWORDS |= {"PROPERTIES", "SYMMETRY", "VIEW", "CONSTRAINT", "CONSTRAINTS", "ACTION_CONSTRAINT", "CHECK_DEADLOCK"}


def msg(code, /, **kw):
    """端末に出す文言をコードから引く(文言をこの表1か所に集める)。"""
    return MESSAGES.get(code, "未知のメッセージコード: " + code).format(**kw)


def invariants(cfg):
    names, on = [], False
    for tok in re.sub(r"\\\*.*", "", cfg).split():
        if tok in KEYWORDS:
            on = tok in ("INVARIANT", "INVARIANTS")
        elif on:
            names.append(tok)
    return names


def without(cfg, rule):
    """The cfg with one invariant name dropped (an INVARIANT line left empty is dropped too)."""
    lines, in_inv = [], False
    for line in cfg.splitlines():
        toks = line.split()
        if toks and toks[0] in KEYWORDS:
            in_inv = toks[0] in ("INVARIANT", "INVARIANTS")
        lines.append([t for t in toks if not (in_inv and t == rule)] if in_inv else toks)
    out = []
    for i, toks in enumerate(lines):
        follow = next((t for t in lines[i + 1 :] if t), None)
        if toks in (["INVARIANT"], ["INVARIANTS"]) and (follow is None or follow[0] in KEYWORDS):
            continue  # a keyword left with no name under it
        out.append(" ".join(toks))
    return "\n".join(out) + "\n"


def state_label(lines):
    pairs = [re.match(r"\s*(?:/\\\s*)?(\w+)\s*=\s*(.+)", ln) for ln in lines]
    pairs = [(m.group(1), m.group(2).strip()) for m in pairs if m]
    if len(pairs) == 1:
        return pairs[0][1]
    return ", ".join(f"{k}={v}" for k, v in pairs)


def trace(out):
    """[(action, label)] of the error trace TLC printed (its search is breadth-first, so it is a shortest path)."""
    steps = []
    for block in re.split(r"^State \d+: ", out, flags=re.M)[1:]:
        head, *rest = block.splitlines()
        action = re.match(r"<(\w+)", head)
        body = []
        for ln in rest:
            if not ln.strip():
                break
            body.append(ln)
        name = action.group(1) if action and action.group(1) != "Initial" else None
        steps.append((name, state_label(body)))
    return steps


def read_dot(text):
    nodes = {m.group(1): state_label(m.group(2).replace("\\n", "\n").replace("\\\\", "\\").splitlines())
             for m in re.finditer(r'^(-?\d+) \[label="(.*?)"', text, re.M)}  # fmt: skip
    edges = [
        (m.group(1), m.group(2), m.group(3)) for m in re.finditer(r'^(-?\d+) -> (-?\d+) \[label="(\w*)"', text, re.M)
    ]
    return nodes, edges


def mermaid(nodes, edges, broken):
    """Mermaid text; states on a path to a broken rule and the breaking state itself are marked."""
    ids = {n: f"s{i}" for i, n in enumerate(sorted(nodes, key=lambda n: (len(nodes[n]), nodes[n])))}
    lines = ["stateDiagram-v2"]
    lines += [f"  {ids[n]}: {nodes[n] or '(空)'}" for n in ids]
    seen = set()
    for a, b, action in edges:
        if a != b and (a, b, action) not in seen and a in ids and b in ids:
            seen.add((a, b, action))
            lines.append(f"  {ids[a]} --> {ids[b]}: {action}")
    labels = {nodes[n]: ids[n] for n in ids}
    lines.append("  classDef breaks fill:#ffecee,stroke:#e72e3b,stroke-width:2px")
    lines.append("  classDef path stroke:#e72e3b,stroke-dasharray:4")
    for steps in broken.values():
        for _action, label in steps[:-1]:
            if label in labels:
                lines.append(f"  class {labels[label]} path")
        if steps and steps[-1][1] in labels:
            lines.append(f"  class {labels[steps[-1][1]]} breaks")
    return "\n".join(lines) + "\n"


def run_tlc(work, name, cfg_text, dump=None):
    (work / f"{name}.cfg").write_text(cfg_text)
    cmd = ["tlc", "-deadlock", "-metadir", str(work / "states")]
    if dump:
        cmd += ["-dump", "dot,actionlabels", str(dump)]
    out = subprocess.run([*cmd, f"{name}.tla"], cwd=work, capture_output=True, text=True, check=False)
    return out.returncode, out.stdout + out.stderr


def check(spec_dir, name):
    """(held, broken {rule: steps}, unchecked, nodes, edges, error tail or None)."""
    work = Path(tempfile.mkdtemp(prefix="hymme-chart-"))
    try:
        for p in Path(spec_dir).glob("*.tla"):
            shutil.copy2(p, work / p.name)
        cfg = (Path(spec_dir) / f"{name}.cfg").read_text()
        rules, broken = invariants(cfg), {}
        for _ in range(len(rules) + 1):
            dump = work / "g.dot"
            _code, out = run_tlc(work, name, cfg, dump)
            m = re.search(r"Invariant (\S+) is violated", out)
            if m:
                broken[m.group(1)] = trace(out)
                cfg = without(cfg, m.group(1))
                continue
            if "Temporal properties were violated" in out:
                broken["(時相の性質)"] = []
            elif "Model checking completed" not in out:
                return (
                    [],
                    broken,
                    [r for r in rules if r not in broken],
                    {},
                    [],
                    "\n".join(out.strip().splitlines()[-12:]),
                )
            nodes, edges = read_dot(dump.read_text()) if dump.exists() else ({}, [])
            return [r for r in rules if r not in broken], broken, [], nodes, edges, None
        return [], broken, [r for r in rules if r not in broken], {}, [], None
    finally:
        shutil.rmtree(work, ignore_errors=True)


def spec_hash(spec_dir, name):
    h = hashlib.sha256()
    for ext in (".tla", ".cfg"):
        h.update((Path(spec_dir) / f"{name}{ext}").read_bytes())
    return h.hexdigest()


def report(name, digest, held, broken, unchecked, nodes, edges):
    lines = [
        f"# {name} の状態の図",
        "",
        f"spec: {digest}",
        f"到達した状態: {len(nodes)}",
        f"検査されなかった規則: {len(unchecked)}",
        "",
    ]
    lines.append("## 破れた規則")
    lines.append("")
    if not broken:
        lines.append("なし")
    for rule, steps in broken.items():
        lines += [f"### {rule}", "", f"最短の経路は {max(len(steps) - 1, 0)} 手です。", ""]
        lines += [f"{i}. {(a + ': ') if a else ''}{label}" for i, (a, label) in enumerate(steps)]
        lines.append("")
    lines += ["", "## 守られた規則", ""] + ([f"- {r}" for r in held] or ["なし"])
    lines += ["", "## 検査されなかった規則", ""] + ([f"- {r}" for r in unchecked] or ["なし"])
    lines += ["", "## 図", ""]
    if len(nodes) > MAX_STATES:
        lines.append(f"状態が {MAX_STATES} を超えるので、図は描いていません。モデルを小さくすると全体が描けます。")
    else:
        lines += ["```mermaid", mermaid(nodes, edges, broken).rstrip(), "```"]
    return "\n".join(lines) + "\n"


def main(spec_dir, name):
    spec_dir = Path(spec_dir)
    for ext in (".tla", ".cfg"):
        if not (spec_dir / f"{name}{ext}").exists():
            print(msg("no_spec", path=spec_dir / f"{name}{ext}"), file=sys.stderr)
            return 2
    if not shutil.which("tlc"):
        print(msg("no_tlc"), file=sys.stderr)
        return 2
    held, broken, unchecked, nodes, edges, err = check(spec_dir, name)
    if err:
        print(msg("tlc_error", tail=err), file=sys.stderr)
        return 2
    out = spec_dir / f"{name}.chart.md"
    out.write_text(report(name, spec_hash(spec_dir, name), held, broken, unchecked, nodes, edges), encoding="utf-8")
    mmd = spec_dir / f"{name}.chart.mmd"
    mmd.write_text(mermaid(nodes, edges, broken), encoding="utf-8")
    print(msg("wrote", report=out, chart=mmd, broken=len(broken), unchecked=len(unchecked)))
    return 1 if broken or unchecked else 0
