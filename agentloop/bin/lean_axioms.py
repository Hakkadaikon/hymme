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
import contextlib
import io
import os
import subprocess
import sys
import tempfile
import unittest.mock
from pathlib import Path

STANDARD = {"propext", "Classical.choice", "Quot.sound"}
MARK = "HYMME-AXIOMS"
MESSAGES = {
    "no_modules": "{project} に Lean のファイルが無い。",
    "stale": "ビルドの結果が無いか、ソースより古い: {mods}。"
    "検査が読むのはビルドの結果なので、先に `lake build` を通す。"
    "通しても同じなら、そのファイルはビルドの対象に入っていない(ライブラリのルートの import に足す)。",
    "lean_failed": "Lean が公理を列挙できなかった(終了コード {code})。先に `lake build` を通す。"
    "ビルドの対象でない .lean がプロジェクトに在ると、ここで読めずに止まる。\n{tail}",
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


def stale(project, mods):
    """Modules whose source is newer than what was built from it: Lean reads the built file and never looks."""
    out = []
    for mod in mods:
        rel = Path(*mod.split("."))
        built = Path(project) / ".lake" / "build" / "lib" / "lean" / rel.with_suffix(".olean")
        source = Path(project) / rel.with_suffix(".lean")
        if not built.exists() or built.stat().st_mtime < source.stat().st_mtime:
            out.append(mod)
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
    IO.println s!"{MARK}\\tseen\\t{{n}}"
    if let .axiomInfo _ := info then
      IO.println s!"{MARK}\\tdeclared\\t{{n}}"
    for a in (← liftCoreM (collectAxioms n)) do
      IO.println s!"{MARK}\\tuses\\t{{n}}\\t{{a}}"
"""


def problems(output):
    """(reasons to stop, number of declarations seen) from the output of the check file."""
    declared, uses, seen = [], {}, 0
    for line in output.splitlines():
        # tab-separated: a Lean name may hold spaces («my thm»)
        mark, kind, name, axiom = (line.split("\t") + [None] * 4)[:4]
        if mark != MARK or not name:
            continue
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
    def out(*rows):
        return "".join("\t".join((MARK, *row.split("|"))) + "\n" for row in rows)

    clean = out("seen|good", "uses|good|propext", "uses|good|Quot.sound") + "noise\n"
    dirty = (
        out("seen|Demo.cheat", "declared|Demo.cheat", "uses|Demo.cheat|Demo.cheat")
        + out("seen|viaAxiom", "uses|viaAxiom|Demo.cheat")
        + out("seen|holed", "uses|holed|sorryAx", "uses|holed|propext")
        + out("seen|«my thm»", "uses|«my thm»|sorryAx")
    )
    cases = [
        ("clean output passes", problems(clean) == ([], 1)),
        ("a declared axiom is reported once", len([p for p in problems(dirty)[0] if "Demo.cheat" in p]) == 1),
        ("sorry is reported", any("holed" in p and "sorryAx" in p for p in problems(dirty)[0])),
        ("a name with a space is reported", any("«my thm»" in p for p in problems(dirty)[0])),
        ("a standard axiom is not reported", not any("propext" in p for p in problems(dirty)[0])),
        ("nested modules are imported", "import «A».«B»" in check_source(["A", "A.B"])),
    ]
    with tempfile.TemporaryDirectory() as tmp:
        source, built = Path(tmp) / "A.lean", Path(tmp) / ".lake" / "build" / "lib" / "lean" / "A.olean"
        source.write_text("theorem t : 1 = 1 := rfl\n", encoding="utf-8")
        cases.append(("a module that was never built is stale", stale(tmp, ["A"]) == ["A"]))
        built.parent.mkdir(parents=True)
        built.write_bytes(b"")
        os.utime(source, (1000, 1000))
        os.utime(built, (2000, 2000))
        cases.append(("a module built after its last edit is fresh", stale(tmp, ["A"]) == []))
        os.utime(source, (3000, 3000))
        cases.append(("a module edited after the build is stale", stale(tmp, ["A"]) == ["A"]))

        def exit_with(code, output):
            """main() on a fresh build, with Lean answering <output> and exiting <code>."""
            lean = subprocess.CompletedProcess([], code, stdout=output, stderr="")
            with unittest.mock.patch.object(subprocess, "run", return_value=lean):
                with contextlib.redirect_stderr(io.StringIO()), contextlib.redirect_stdout(io.StringIO()):
                    return main([tmp])

        cases.append(("a stale project is not checked", exit_with(0, clean) == 2))
        os.utime(built, (4000, 4000))
        cases.append(("Lean printing nothing is not a pass", exit_with(0, "") == 2))
        cases.append(("Lean failing is not a pass", exit_with(1, clean) == 2))
        cases.append(("an unproven premise exits 1", exit_with(0, dirty) == 1))
        cases.append(("standard axioms only exits 0", exit_with(0, clean) == 0))
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
    old = stale(args.project, mods)
    if old:
        print(msg("stale", mods=", ".join(old)), file=sys.stderr)
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
