#!/usr/bin/env python3
"""Verifiability metrics: is the code about to be verified shaped so a model can mirror it?

A model (Z3 claim, TLA+ action, Lean def) is only as trustworthy as its mapping
to the code. The mapping is easy when the decision lives in small pure
functions, and error-prone when branches pile up, I/O and clocks are mixed in,
or errors are silently folded into booleans. This measures exactly that for
the functions a ledger names as the decision core.

Ledger (`tasks/verifiability/<Name>.md`):
    ## 対象
    - path/to/file.py::function     one line per function the model will mirror
    (or the single line `対象コード無し: <理由>` for design-only verification)
    ## 例外
    - path/to/file.py::function <指標>: <理由>   waive one metric for one function

Metrics per target (thresholds below): CCN, NLOC, parameters (self/cls not
counted), side effects (I/O, clock, randomness, module-level mutable state),
errors folded into a boolean (an except/catch that returns true/false).
Side effects and folding are found in .py (syntax tree + tokens) and in
.js/.ts/.jsx/.tsx/.go/.rs/.java (tokens). Other languages fail both metrics as
unmeasurable until a waiver says how the model treats them.
Name a method as Class.method when the bare name is ambiguous.

Usage:
    verifiability.py <ledger.md>       paths in the ledger are relative to the cwd
    verifiability.py --selfcheck

Exit: 0 every target passes or is waived, 1 a metric fails, 2 bad ledger
(missing section, unknown function, waiver without a reason).
"""

import ast
import re
import sys
from pathlib import Path

import lizard

MESSAGES = {
    "usage": "使い方: verifiability.py <台帳.md>  (台帳の中のパスは cwd からの相対)\n"
    "       verifiability.py --selfcheck\n"
    "exit: 0 全対象が合格か例外、1 指標が不合格、2 台帳の誤り(節が無い、関数が無い、例外に理由が無い)",
    "no_section": "{path}: 「## 対象」節が無い",
    "no_targets": "{path}: 「## 対象」に `- path::function` も「対象コード無し: 理由」も無い",
    "bad_metric": "例外 {target}: 指標 {metric!r} は {metrics} のどれでもない",
    "no_reason": "例外 {target} {metric}: 理由が無い",
    "no_function": "{path}: 関数 {name} が見つからない",
    "ambiguous": "{path}: {name} が複数ある({hits})。Class.method の形で指定する"
    "(Go の型違いの同名メソッドとオーバーロードは区別できないので、判定を別名の関数に切り出す)",
    "no_file": "{path}: ファイルが無い",
    "bad_path": "{path}: リポジトリ直下からの相対パスで、その配下の通常ファイルを書く",
    "unmeasurable": "{suffix} は測れない(モデル側でどう扱うかを例外に書き、目で確かめる)",
    "no_suffix": "拡張子なし",
    "module_var": "モジュール変数 {name}",
    "imported": "import した {name}",
    "line": "{no} 行目",
    "catch_bool": "catch/recover が真偽値を返す",
    "over_limit": "{metric} {value} > {limit}",
    "finding": "{metric}: {items}",
    "waived": "{problem} (例外: {reason})",
    "result": "{verdict} {target}  [CCN {ccn}, NLOC {nloc}, 引数 {args}]",
    "pass": "合格",
    "fail": "不合格",
    "no_code": "合格 対象コード無し: {reason}",
    "error": "エラー: {error}",
    "selfcheck_ok": "自己検査 合格",
}


def msg(code, **kw):
    """端末に出す文言をコードから引く(文言をこの表1か所に集める)。"""
    return MESSAGES[code].format(**kw)


LIMITS = {"CCN": 10, "NLOC": 50, "引数": 5}
SIDE = "副作用"
FOLD = "エラーを真偽値に畳む"
METRICS = (*LIMITS, SIDE, FOLD)

# shortcut: token patterns, not data flow; a waiver with a reason covers false positives.
SIDE_MODULES = (
    "requests",
    "urllib",
    "socket",
    "subprocess",
    "os",
    "sys",
    "shutil",
    "logging",
    "time",
    "datetime",
    "random",
    "uuid",
    "secrets",
)
SIDE_PATTERNS = {
    ".py": r"\b(open|print|input)\s*\(|\b(" + "|".join(SIDE_MODULES) + r")\.|\b(global|nonlocal)\b",
    ".js": r"\b(fetch|require)\s*\(|\b(fs|console|process|localStorage|document|window|crypto)\.|"
    r"\bDate\.now\b|\bnew Date\s*\(|\bMath\.random\b",
    ".go": r"\b(os|io|ioutil|net|http|log|fmt|rand|syscall)\.|\btime\.(Now|Since|Sleep)\b",
    ".rs": r"\b(std::(fs|io|net|env|process|time)|println!|eprintln!|rand::|SystemTime::now|Instant::now)",
    ".java": r"\bSystem\.(out|err|currentTimeMillis|nanoTime|getenv)\b|\bnew (File|Random|Socket)\b|"
    r"\bLocalDateTime\.now\b",
}
SIDE_PATTERNS[".ts"] = SIDE_PATTERNS[".tsx"] = SIDE_PATTERNS[".jsx"] = SIDE_PATTERNS[".js"]
FOLD_PATTERN = (
    r"(catch\s*(\([^)]*\))?\s*\{[^}]*return\s+(true|false)\b)|"
    r"(unwrap_or\((true|false)\))|(recover\(\)[\s\S]*return\s+(true|false)\b)"
)


class LedgerError(Exception):
    pass


def section(text, title):
    m = re.search(rf"^## {title}\s*$(.*?)(?=^## |\Z)", text, re.M | re.S)
    return m.group(1) if m else None


def read_ledger(path):
    text = Path(path).read_text()
    targets = section(text, "対象")
    if targets is None:
        raise LedgerError(msg("no_section", path=path))
    no_code = re.search(r"^対象コード無し(?:\(実装後\))?[:：]\s*(\S.*)$", targets, re.M)
    items = re.findall(r"^- (\S+?)::(\S+)", targets, re.M)
    if no_code and not items:
        return "no-code", no_code.group(1), {}
    if not items:
        raise LedgerError(msg("no_targets", path=path))
    waivers = {}
    for line in (section(text, "例外") or "").splitlines():
        m = re.match(r"^- (\S+?::\S+)\s+(\S+?)[:：]\s*(.*)$", line)
        if not m:
            continue
        target, metric, reason = m.groups()
        if metric not in METRICS:
            raise LedgerError(msg("bad_metric", target=target, metric=metric, metrics=", ".join(METRICS)))
        if not reason.strip():
            raise LedgerError(msg("no_reason", target=target, metric=metric))
        waivers[(target, metric)] = reason.strip()
    return "targets", items, waivers


def find_function(path, name):
    """The one function the ledger names: exact name, or Class.method / Class::method."""
    info = lizard.analyze_file(str(path))
    if path.suffix == ".py" and "." in name:  # lizard names Python methods without their class
        cls, meth = name.rsplit(".", 1)
        lines = {
            f.lineno
            for c in ast.walk(ast.parse(path.read_text()))
            if isinstance(c, ast.ClassDef) and c.name == cls
            for f in c.body
            if isinstance(f, (ast.FunctionDef, ast.AsyncFunctionDef)) and f.name == meth
        }
        hits = [f for f in info.function_list if f.start_line in lines]
    else:  # lizard names Java/C#/C++ methods Class::method; accept Class.method for them too
        want = name.replace(".", "::")
        hits = [f for f in info.function_list if f.name in (name, want) or re.split(r"\.|::", f.name)[-1] == name]
    if not hits:
        raise LedgerError(msg("no_function", path=path, name=name))
    if len(hits) > 1:
        raise LedgerError(msg("ambiguous", path=path, name=name, hits=", ".join(f.name for f in hits)))
    return hits[0]


MUTABLE_CALLS = {"dict", "list", "set", "bytearray", "defaultdict", "OrderedDict", "Counter", "deque"}


def python_findings(tree, start_line):
    """Module-level mutable state and side-effect imports the function reads, and except-handlers returning a bool."""
    mutable, imported = set(), set()
    for node in tree.body:
        value, names = None, []
        if isinstance(node, ast.Assign):
            value, names = node.value, [t.id for t in node.targets if isinstance(t, ast.Name)]
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            value, names = node.value, [node.target.id]
        if isinstance(value, (ast.Dict, ast.List, ast.Set)) or (
            isinstance(value, ast.Call) and getattr(value.func, "id", getattr(value.func, "attr", "")) in MUTABLE_CALLS
        ):
            mutable.update(names)
        if isinstance(node, ast.ImportFrom) and (node.module or "").split(".")[0] in SIDE_MODULES:
            imported.update(a.asname or a.name for a in node.names)
        if isinstance(node, ast.Import):  # import time as t: t.time() escapes the "time." token
            imported.update(a.asname for a in node.names if a.asname and a.name.split(".")[0] in SIDE_MODULES)
    func = next(
        (
            n
            for n in ast.walk(tree)
            if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
            and start_line in (n.lineno, *(d.lineno for d in n.decorator_list))
        ),
        None,
    )
    if func is None:
        return [], []
    a = func.args
    params = {x.arg for x in a.posonlyargs + a.args + a.kwonlyargs + [a.vararg, a.kwarg] if x}
    assigned = {n.id for n in ast.walk(func) if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Store)}
    used = {n.id for n in ast.walk(func) if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Load)} - params - assigned
    side = [msg("module_var", name=n) for n in sorted(used & mutable)]
    side += [msg("imported", name=n) for n in sorted(used & imported)]
    fold = [
        msg("line", no=h.lineno)
        for h in ast.walk(func)
        if isinstance(h, ast.ExceptHandler)
        and any(
            isinstance(r, ast.Return) and isinstance(r.value, ast.Constant) and isinstance(r.value.value, bool)
            for r in ast.walk(h)
        )
    ]
    return side, fold


def is_method(source, line):
    return any(
        isinstance(c, ast.ClassDef)
        and any(isinstance(f, (ast.FunctionDef, ast.AsyncFunctionDef)) and f.lineno == line for f in c.body)
        for c in ast.walk(ast.parse(source))
    )


def measure(path, name):
    path = Path(path)
    if not path.exists():
        raise LedgerError(msg("no_file", path=path))
    # the hook runs this on any ledger; keep it to regular files under the ledger's root (no /dev/zero, no ..)
    root = Path.cwd().resolve()
    if path.is_absolute() or root not in path.resolve().parents or not path.resolve().is_file():
        raise LedgerError(msg("bad_path", path=path))
    f = find_function(path, name)
    source = path.read_text()
    body = "\n".join(source.splitlines()[f.start_line - 1 : f.end_line])
    params = list(f.parameters)
    if path.suffix == ".py" and params[:1] in (["self"], ["cls"]) and is_method(source, f.start_line):
        params = params[1:]
    m = {"CCN": f.cyclomatic_complexity, "NLOC": f.nloc, "引数": len(params)}
    if path.suffix not in SIDE_PATTERNS:
        unmeasured = [msg("unmeasurable", suffix=path.suffix or msg("no_suffix"))]
        return {**m, SIDE: unmeasured, FOLD: unmeasured}
    side = sorted(set(x.group(0).strip() for x in re.finditer(SIDE_PATTERNS[path.suffix], body)))
    fold = [msg("catch_bool")] if path.suffix != ".py" and re.search(FOLD_PATTERN, body) else []
    if path.suffix == ".py":
        pside, pfold = python_findings(ast.parse(source), f.start_line)
        side += pside
        fold += pfold
    return {**m, SIDE: side, FOLD: fold}


def evaluate(items, waivers):
    """(exit code, report lines)."""
    lines, failed = [], False
    for path, name in items:
        target = f"{path}::{name}"
        m = measure(path, name)
        problems = []
        for k, limit in LIMITS.items():
            if m[k] > limit:
                problems.append((k, msg("over_limit", metric=k, value=m[k], limit=limit)))
        for k in (SIDE, FOLD):
            if m[k]:
                problems.append((k, msg("finding", metric=k, items=", ".join(m[k]))))
        open_problems = [(k, p) for k, p in problems if (target, k) not in waivers]
        waived = [msg("waived", problem=p, reason=waivers[(target, k)]) for k, p in problems if (target, k) in waivers]
        verdict = msg("fail") if open_problems else msg("pass")
        failed |= bool(open_problems)
        lines.append(msg("result", verdict=verdict, target=target, ccn=m["CCN"], nloc=m["NLOC"], args=m["引数"]))
        lines += [f"    {p}" for _, p in open_problems] + [f"    {w}" for w in waived]
    return (1 if failed else 0), lines


def _selfcheck():
    """assert-based check of the ledger parser and the Python findings. Run: --selfcheck"""
    src = "S = {}\ndef f(x):\n    try:\n        return x in S\n    except KeyError:\n        return False\n"
    assert python_findings(ast.parse(src), 2) == (["モジュール変数 S"], ["5 行目"]), python_findings(ast.parse(src), 2)
    assert python_findings(ast.parse("def g(S):\n    return S\n"), 1) == ([], [])
    src = (
        "import re\nfrom time import time as now\nP = re.compile('x')\nC: dict = {}\n"
        "def h(x):\n    return P.match(x) and now() in C\n"
    )
    assert python_findings(ast.parse(src), 5) == (["モジュール変数 C", "import した now"], []), python_findings(
        ast.parse(src), 5
    )
    src = "import time as t\nS = {}\ndef k(x, /):\n    S = set()\n    return x in S and t.time()\n"
    assert python_findings(ast.parse(src), 3) == (["import した t"], []), python_findings(ast.parse(src), 3)
    assert section("## 対象\n- a::b\n## 例外\n", "対象").strip() == "- a::b"
    print(msg("selfcheck_ok"))


def main():
    if sys.argv[1:] == ["--selfcheck"]:
        _selfcheck()
        return 0
    if len(sys.argv) != 2:
        print(msg("usage"), file=sys.stderr)
        return 2
    try:
        kind, items, waivers = read_ledger(sys.argv[1])
        if kind == "no-code":
            print(msg("no_code", reason=items))
            return 0
        code, lines = evaluate(items, waivers)
    except (LedgerError, OSError, SyntaxError) as e:
        print(msg("error", error=e), file=sys.stderr)
        return 2
    print("\n".join(lines))
    return code


if __name__ == "__main__":
    sys.exit(main())
