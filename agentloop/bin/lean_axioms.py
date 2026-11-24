#!/usr/bin/env python3
"""Axiom check: list what every declaration of a Lean project rests on, and stop on anything unproven.

A proof assistant accepts a statement nobody proved in three ways: `sorry`, an `axiom` the project
declares itself, and a compiled decision trusted as a proof (`native_decide`). `lake build` passes on
all three. This asks Lean which axioms each declaration of the project depends on, transitively, and
fails unless they are the three axioms of the standard library.

Usage:
    lean_axioms.py <project dir>     (after `lake build`; runs `lake env lean` in the project)
    lean_axioms.py --selfcheck

Exit: 0 every declaration rests on the standard axioms only, 1 some declaration does not,
2 the project could not be checked (no Lean file, not built, Lean failed).
"""

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

STANDARD = {"propext", "Classical.choice", "Quot.sound"}
MARK = "HYMME-AXIOMS"
MESSAGES = {
    "no_modules": "{project} に Lean のファイルが無い。",
    "lean_failed": "Lean が公理を列挙できなかった(終了コード {code})。先に `lake build` を通す。\n{tail}",
    "declared": "プロジェクトが公理を宣言している: {name}。証明するか、命題から外す。",
    "uses": "{name} は証明されていない前提に依存している: {axioms}。",
    "ok": "{n} 個の宣言を調べた。依存する公理は標準の3つ(propext, Classical.choice, Quot.sound)だけ。",
    "selfcheck_ok": "selfcheck: ok",
    "selfcheck_ng": "selfcheck: {what}",
}


def msg(code, /, **kw):
    """端末に出すメッセージをコードから引く(メッセージをこの表1か所に集める)。"""
    return MESSAGES.get(code, "未知のメッセージコード: " + code).format(**kw)


def modules(project):
    """Module names of the project's own Lean files (dependencies under .lake and the lakefile aside)."""
    out = []
    for path in sorted(Path(project).rglob("*.lean")):
        rel = path.relative_to(project)
        if rel.parts[0] == ".lake" or rel.name == "lakefile.lean":
            continue
        out.append(".".join(rel.with_suffix("").parts))
    return out


def check_source(mods):
    """A Lean file that prints, for every constant the given modules define, the axioms it depends on."""
    imports = "\n".join(f"import «{'».«'.join(m.split('.'))}»" for m in mods)
    names = ", ".join("`" + ".".join(f"«{part}»" for part in m.split(".")) for m in mods)
    return f"""import Lean
{imports}
open Lean Elab Command in
run_cmd do
  let env ← getEnv
  let mine : List Name := [{names}]
  for (n, info) in env.constants.map₁.toList do
    let some idx := env.getModuleIdxFor? n | continue
    if !mine.contains env.header.moduleNames[idx.toNat]! then continue
    IO.println s!"{MARK} seen {{n}}"
    if let .axiomInfo _ := info then
      IO.println s!"{MARK} declared {{n}}"
    for a in (← liftCoreM (collectAxioms n)) do
      IO.println s!"{MARK} uses {{n}} {{a}}"
"""


def problems(output):
    """(reasons to stop, number of declarations seen) from the output of the check file."""
    declared, uses, seen = [], {}, 0
    for line in output.splitlines():
        m = re.match(rf"{MARK} (seen|declared|uses) (\S+)(?: (\S+))?$", line)
        if not m:
            continue
        kind, name, axiom = m.groups()
        if kind == "seen":
            seen += 1
        elif kind == "declared":
            declared.append(name)
        elif axiom not in STANDARD and name != axiom:
            uses.setdefault(name, []).append(axiom)
    out = [msg("declared", name=n) for n in sorted(declared)]
    # a declared axiom is reported once above, not again for every theorem that uses it
    out += [
        msg("uses", name=n, axioms=", ".join(sorted(set(a))))
        for n, a in sorted(uses.items())
        if n not in declared and set(a) - set(declared)
    ]
    return out, seen


def selfcheck():
    clean = f"{MARK} seen good\n{MARK} uses good propext\n{MARK} uses good Quot.sound\nnoise\n"
    dirty = (
        f"{MARK} seen Demo.cheat\n{MARK} declared Demo.cheat\n{MARK} uses Demo.cheat Demo.cheat\n"
        f"{MARK} seen viaAxiom\n{MARK} uses viaAxiom Demo.cheat\n"
        f"{MARK} seen holed\n{MARK} uses holed sorryAx\n{MARK} uses holed propext\n"
    )
    cases = [
        ("clean output passes", problems(clean) == ([], 1)),
        ("a declared axiom is reported once", len([p for p in problems(dirty)[0] if "Demo.cheat" in p]) == 1),
        ("sorry is reported", any("holed" in p and "sorryAx" in p for p in problems(dirty)[0])),
        ("a standard axiom is not reported", not any("propext" in p for p in problems(dirty)[0])),
        ("nested modules are imported", "import «A».«B»" in check_source(["A", "A.B"])),
    ]
    bad = [what for what, ok in cases if not ok]
    print(msg("selfcheck_ng", what=", ".join(bad)) if bad else msg("selfcheck_ok"))
    return 1 if bad else 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("project", nargs="?")
    ap.add_argument("--selfcheck", action="store_true")
    args = ap.parse_args(argv)
    if args.selfcheck:
        return selfcheck()
    if not args.project:
        ap.error("project dir is required")
    mods = modules(args.project)
    if not mods:
        print(msg("no_modules", project=args.project), file=sys.stderr)
        return 2
    with tempfile.NamedTemporaryFile("w", suffix=".lean", encoding="utf-8") as f:
        f.write(check_source(mods))
        f.flush()
        run = subprocess.run(
            ["lake", "env", "lean", f.name], cwd=args.project, capture_output=True, text=True, check=False
        )
    found, seen = problems(run.stdout)
    # zero declarations seen means the check itself did not run, whatever the exit code says
    if run.returncode != 0 or seen == 0:
        tail = "\n".join((run.stdout + run.stderr).splitlines()[-10:])
        print(msg("lean_failed", code=run.returncode, tail=tail), file=sys.stderr)
        return 2
    if found:
        print("\n".join(found), file=sys.stderr)
        return 1
    print(msg("ok", n=seen))
    return 0


if __name__ == "__main__":
    sys.exit(main())
