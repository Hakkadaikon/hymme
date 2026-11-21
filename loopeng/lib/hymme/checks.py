"""The checks a hook runs. Each returns a list of reasons to stop ([] lets the tool call through).

A check reads only records whose signature verifies, so a line a worker appended to the log by hand
does not count. `ctx` carries what one hook invocation knows: cwd, the signing key, the parsed command.
"""

import re
import subprocess
import time
from pathlib import Path

from . import chart, ledgers, store

MESSAGES = {
    "claims_missing": "ユーザーの確認ゲート: {path} が無い。要件ごとに「示すこと」「示さないこと」「破れたときの害」を書き、"
    "`hymme claims request {name}` でユーザーに承認を求めてから検証へ進む。",
    "claims_invalid": "ユーザーの確認ゲート: {path} はユーザーに見せられる形になっていない: {why}",
    "claims_unapproved": "ユーザーの確認ゲート: {name} の一覧はユーザーの承認が無い(承認のあとに一覧を変えた場合も同じ)。"
    "`hymme claims request {name}` を実行し、表示された1行をユーザーに入力してもらう。"
    "ユーザーと対話できない実行(サブエージェント、無人の実行)は、ここで止めて BLOCKED で返す。",
    "extract_missing": "0段ゲート: 抽出の台帳 {path} が無い。loopeng-extract の手順で台帳を完成させてから進む。",
    "extract_open": "0段ゲート: {path} が閉じていない: {why}",
    "review_missing": "検証容易性ゲート: {name} の reviewer の合格が記録されていない(台帳か対象のコードを合格のあとに変えた場合も同じ)。"
    "hymme:verification-reviewer(対象 verifiability)を dispatch し、最後の行に「判定: 合格 対象=verifiability 名前={name}」が返るまで往復する。",
    "premise": "前提の確認ゲート: {name} は修正を挟んでも同じ規則({rule})で2回続けて落ちた。次の修正の前に、"
    "失敗した修正が共通して置いていた前提を {path} に1文で書き、その前提が偽なら結果が変わる観測を1つ行って結果を書く。",
    "no_review": "統合ゲート: この変更に対する diff-review の記録が無い。diff-review スキルを実行する(レビュー担当の最後の行の must と lenses を hook が記録する)。",
    "must_left": "統合ゲート: diff-review の must 指摘が {n} 件残っている(レンズ: {lenses})。直して再レビューする。",
    "claim_only": "統合ゲート: 確かさの段階が「主張のみ」の指摘か主張が {n} 件ある(レンズ: {lenses})。実行で確かめるか、取り下げて再レビューする。",
    "escape_open": "統合ゲート: 閉じていない欠陥の記録がある: {ids}。前の段にテストを足し、`hymme escape verify <id>` を通して閉じる。",
    "fix_without_escape": "統合ゲート: fix 型のコミットがあるのに欠陥の記録が1件も無い。`hymme escape open` で記録を開き、再現と前段のテストを通す。",
    "stale": "統合ゲート: {name} の検証が写したコード({paths})がこの変更で変わっている。変更を「影響なし / 記述が合わなくなった / 約束を意図して変えた / "
    "約束が破れたおそれ」に分け、検証を今のコードに対して実行し直す(必要な実行: {need})。",
    "trace_missing": "統合ゲート: {name} の実ログの突き合わせが足りない(足りないもの: {need})。正常系、高負荷、障害注入のログが通り、"
    "わざと壊した実装のログが不一致になることを、`trace_check.py` を直接実行して示す。ログの名前は <名前>.normal.jsonl / .load.jsonl / .fault.jsonl / .broken.jsonl。"
    "ログの粒度が spec と合わないときは、コマンド1つを1ステップで写す spec を別に作り、元の検証容易性の台帳に「実ログの spec: <その名前>」と書く。",
    "chart_missing": "ユーザーの確認ゲート: {name} の状態遷移図が無いか、今の spec から作られていない。`hymme chart draw {name}` で作り直す。",
    "chart_open": "ユーザーの確認ゲート: {name} の状態遷移図に、破れた規則か検査されなかった規則が残っている。設計を直して `hymme chart draw {name}` をやり直す。",
    "chart_unapproved": "ユーザーの確認ゲート: {name} の状態遷移図はユーザーの承認が無い。`hymme chart request {name}` を実行し、表示された1行をユーザーに入力してもらう。",
    "log_not_captured": "統合ゲート: {name} の実ログ({labels})は `hymme capture` で採ったものではない。`hymme capture <ログ> -- <実システムを動かすコマンド>` で採り直す。",
    "no_stages": "統合ゲート: tasks/stages.md に、後段(integration か e2e)のコマンドの宣言が無い。どのコマンドとパスがどの段かを宣言する。"
    "後段のテストが無いリポジトリは、`hymme exception request stages` でユーザーの承認を取る。",
    "no_surface": "統合ゲート: tasks/surface.md が無い。実システムの動かし方(起動、健全性の確認、操作、証跡、後片付け)と「- 確認のコマンド:」を書く。",
    "surface_invalid": "統合ゲート: tasks/surface.md が足りない: {why}",
    "surface_not_run": "統合ゲート: この変更に対して、tasks/surface.md の確認のコマンド({command})が通った記録が無い。実システムを動かして確かめる。",
    "weakened": "統合ゲート: 検査を弱める変更がある({what})。`hymme exception request weaken` でユーザーの承認を取る。",
    "pr_body": "統合ゲート: PR の本文に「{heading}」の見出しが無い。影響の範囲と検証の結果を書く。",
    "protected": "記録の保護: 署名の鍵と記録の置き場({path})は、hymme のツール以外から読み書きできない。",
    "approval_text": "記録の保護: 承認の入力と同じ形の文字列を、ツールの入力に入れることはできない。",
    "no_repo": "統合ゲート: git リポジトリの状態を確認できない。リポジトリの中で実行する。",
}

# checks an approved, dated exception may switch off; a check a worker must answer in person is not here
EXEMPTABLE = {"review", "stages", "surface", "trace", "stale", "weaken", "fix_without_escape", "pr_body"}
APPROVAL = re.compile(r"承認 [0-9a-f]{8}")
TRACE_KINDS = ("normal", "load", "fault", "broken")
WEAKEN = re.compile(
    r"^\+.*(\bskip\b|\bxfail\b|\.only\(|@Ignore|@Disabled|t\.Skip\(|pytest\.mark\.skip|#\s*noqa|eslint-disable)", re.M
)
ASSERT_REMOVED = re.compile(r"^-(?!-).*\b(assert\w*|expect|should)\b", re.M)
ASSERT_ADDED = re.compile(r"^\+(?!\+).*\b(assert\w*|expect|should)\b", re.M)


def msg(code, /, **kw):
    """端末に出すメッセージをコードから引く(メッセージをこの表1か所に集める)。"""
    return MESSAGES.get(code, "未知のメッセージコード: " + code).format(**kw)


class Ctx:
    def __init__(self, cwd, key, gate=None, command=""):
        self.cwd, self.key, self.gate, self.command = cwd, key, gate, command
        self.ref = "HEAD"  # the ref whose change is leaving: the branch being merged, when a merge is checked
        self._change = None

    def recs(self, kind, **match):
        return store.records(self.cwd, self.key, kind=kind, **match)

    def leaving(self, ref):
        """Measure the change of <ref> from here on (the branch a merge brings in, instead of HEAD)."""
        self.ref, self._change = ref, None
        return self

    def change(self):
        if self._change is None:
            self._change = store.change_id(self.cwd, self.ref) or "none"
        return self._change

    def exempt(self, check):
        """An exception a worker approved for this check that has not expired."""
        today = time.strftime("%Y-%m-%d")
        return check in EXEMPTABLE and any(r.get("until", "") >= today for r in self.recs("exception", check=check))


def approved(ctx, root, name):
    """Whether the worker approved the claims list as it stands now."""
    text = ledgers.read(ledgers.claims_path(root, name))
    return text is not None and bool(ctx.recs("approval", type="claims", name=name, hash=ledgers.sha(text)))


def claims(ctx):
    """2-08: every verification entry point needs the worker's approval of what it will show."""
    out = []
    for root, name, _kind in ctx.gate.entries():
        path = ledgers.claims_path(root, name)
        text = ledgers.read(path)
        if text is None:
            out.append(msg("claims_missing", path=path, name=name))
        elif ledgers.claims_problems(text):
            out.append(msg("claims_invalid", path=path, why="; ".join(ledgers.claims_problems(text))))
        elif not approved(ctx, root, name):
            out.append(msg("claims_unapproved", name=name))
        elif _kind == "trace_check" and chart_problem(ctx, root, name):
            out.append(chart_problem(ctx, root, name))
    return out


def chart_problem(ctx, root, name):
    """2-13, 2-14: the chart was drawn from the spec as it is, leaves no rule open, and the worker approved it."""
    spec_dir = Path(root) / "tasks" / "loopeng"
    text = ledgers.read(spec_dir / f"{name}.chart.md")
    try:
        digest = chart.spec_hash(spec_dir, name)
    except OSError:
        digest = None
    if text is None or digest is None or f"spec: {digest}" not in text:
        return msg("chart_missing", name=name)
    if "検査されなかった規則: 0" not in text or not re.search(r"^## 破れた規則\n+なし$", text, re.M):
        return msg("chart_open", name=name)
    if not ctx.recs("approval", type="chart", name=name, hash=ledgers.sha(text)):
        return msg("chart_unapproved", name=name)
    return None


def extract(ctx):
    """0段: the extraction ledger is closed, closing checks included, before the loop tools run."""
    out = []
    for root, name, kind in ctx.gate.entries():
        if kind == "lake":
            continue  # tasks/fv keeps a property catalogue instead; formal-verification's reviewer covers it
        path = Path(root) / "tasks" / "loopeng" / f"{name}.extract.md"
        text = ledgers.read(path)
        if text is None:
            out.append(msg("extract_missing", path=path))
        elif ledgers.extract_problems(text):
            out.append(msg("extract_open", path=path, why="; ".join(ledgers.extract_problems(text))))
    return out


def target_hashes(root, paths):
    return {p: store.sha256_file(Path(root) / p) for p in paths}


def review(ctx):
    """1-10: the verifiability review is a record the hook wrote when the reviewer returned, not a ticked box."""
    out = []
    for root, name, _kind in ctx.gate.entries():
        targets = ledgers.verifiability_targets(root).get(name)
        if not targets:
            continue  # no code to mirror yet; verifiability-gate.sh checks that the ledger says so
        want = {
            "ledger": store.sha256_file(Path(root) / "tasks" / "verifiability" / f"{name}.md"),
            "files": target_hashes(root, targets),
        }
        passed = [r for r in ctx.recs("review", target="verifiability", name=name) if r.get("verdict") == "pass"]
        if not any(r.get("ledger") == want["ledger"] and r.get("files") == want["files"] for r in passed):
            out.append(msg("review_missing", name=name))
    return out


def premise(ctx):
    """4-16: after two failures on the same rule with a fix in between, the premise is written down first."""
    out = []
    for root, name, _kind in ctx.gate.entries():
        # the log of a deliberately broken build is meant to fail; it says nothing about the design
        runs = [r for r in ctx.recs("run", name=name) if r.get("label") != "broken"][-2:]
        if len(runs) < 2 or any(r.get("exit") == 0 or not r.get("rule") for r in runs):
            continue
        a, b = runs
        if a["rule"] != b["rule"] or a.get("inputs") == b.get("inputs"):
            continue  # a different rule, or a plain rerun without a fix in between
        path = Path(root) / "tasks" / "loopeng" / f"{name}.premise.md"
        text = ledgers.read(path) or ""
        f = ledgers.fields(text)
        fresh = path.exists() and path.stat().st_mtime > b["ts"]
        if not (fresh and f.get("前提") and f.get("観測") and f.get("結果")):
            out.append(msg("premise", name=name, rule=b["rule"], path=path))
    return out


def open_escapes(ctx):
    closed = {r["id"] for r in ctx.recs("escape-closed")}
    return sorted({r["id"] for r in ctx.recs("escape-open")} - closed)


def branch_log(cwd, ref="HEAD"):
    base = store.merge_base(cwd, ref)
    if base is None:
        return []
    return store.git("log", "--format=%s", f"{base}..{ref}", cwd=cwd).splitlines()


def branch_diff(cwd, ref="HEAD"):
    base = store.merge_base(cwd, ref)
    if base is None:
        return ""
    return subprocess.run(["git", "diff", base, ref], cwd=cwd, capture_output=True, text=True, check=False).stdout


def weakened(diff):
    """What in a diff weakens a check: a skip added, or more assertions removed than added."""
    what = []
    if WEAKEN.search(diff):
        what.append("テストの skip か検査の無効化を足した")
    if len(ASSERT_REMOVED.findall(diff)) > len(ASSERT_ADDED.findall(diff)):
        what.append("アサーションを足した数より多く消した")
    return what


def stale_names(ctx, root):
    """Names whose mirrored code this branch changed (1-15, 1-16)."""
    changed = store.changed_files(ctx.cwd, ctx.ref)
    return {n: sorted(set(p) & changed) for n, p in ledgers.verifiability_targets(root).items() if set(p) & changed}


def integration(ctx, body=None):
    """What must hold before a change leaves the branch: PR, MR, merge, or a push after the PR exists."""
    try:
        root = store.toplevel(ctx.cwd)
    except store.NoRepo:
        return [msg("no_repo")]
    out, change = [], ctx.change()

    # review: for every set of lenses, the latest reviewer record on this change has no must left
    latest = {}
    for r in ctx.recs("review", target="diff", change=change):
        latest[r.get("lenses", "")] = r
    if not ctx.exempt("review"):
        if not latest:
            out.append(msg("no_review"))
        for lenses, r in latest.items():
            if r.get("must", 0):
                out.append(msg("must_left", n=r["must"], lenses=lenses))
            if r.get("claim_only", 0):
                out.append(msg("claim_only", n=r["claim_only"], lenses=lenses))

    ids = open_escapes(ctx)
    if ids:
        out.append(msg("escape_open", ids=", ".join(ids)))
    # the record belongs to the branch that leaves: the one being merged, or the one checked out.
    # Once fixes sit on the default branch, the branch they were recorded on is gone from view: any record counts.
    here = ctx.ref if ctx.ref != "HEAD" else store.branch(ctx.cwd)
    match = {} if here == store.default_branch(ctx.cwd) else {"branch": here}
    handled = ctx.recs("escape-open", **match) + ctx.recs("escape-closed", **match)
    if not ctx.exempt("fix_without_escape") and not handled:
        if any(re.match(r"fix(\(.+\))?!?:", s) for s in branch_log(ctx.cwd, ctx.ref)):
            out.append(msg("fix_without_escape"))

    what = weakened(branch_diff(ctx.cwd, ctx.ref))
    if what and not ctx.exempt("weaken"):
        out.append(msg("weakened", what="、".join(what)))

    if not ledgers.managed(root):
        return out  # a repository that keeps no hymme ledger is only held to the review and the escape record

    # freshness: a verification whose mirrored code changed must have run again on this change
    for name, paths in stale_names(ctx, root).items():
        if ctx.exempt("stale"):
            break
        ran = {
            r["entry"]
            for r in ctx.recs("run", name=name, change=change)
            if r.get("exit") == 0 and not r.get("inconclusive")
        }
        want = {r["entry"] for r in ctx.recs("run", name=name)} | {"verifiability"}
        if (root / "tasks" / "loopeng" / f"{name}.smt.py").exists():
            want.add("parity")  # 4-13: the real function and the model agree on the inputs that were tried
        need = sorted(want - ran - {"trace_check", "loop-inner", "loop-outer"})
        if need:
            out.append(msg("stale", name=name, paths=", ".join(paths), need=", ".join(need)))

    # real logs: every spec this change touches was checked against logs of the running system
    for name in sorted(stale_names(ctx, root)):
        if not (root / "tasks" / "loopeng" / f"{name}.tla").exists():
            continue
        problem = chart_problem(ctx, root, name)  # the worker's approval: no exception switches it off
        if problem:
            out.append(problem)
        if not ctx.exempt("trace"):
            logged = ledgers.log_spec(root, name)
            runs = ctx.recs("run", name=logged, entry="trace_check", change=change)
            # the log of the broken build must be a mismatch (exit 1), not a run that could not decide (exit 2)
            good = [r for r in runs if r.get("exit") == (1 if r.get("label") == "broken" else 0)]
            need = [k for k in TRACE_KINDS if k not in {r.get("label") for r in good}]
            if need:
                out.append(msg("trace_missing", name=logged, need=", ".join(need)))
            captured = {r.get("log") for r in ctx.recs("capture")}
            loose = sorted({str(r.get("label")) for r in good if r.get("log") not in captured})
            if loose:
                out.append(msg("log_not_captured", name=logged, labels=", ".join(loose)))

    decl = ledgers.stages(root)
    later = [
        s
        for s, _c in (decl or {}).get("commands", [])
        if ledgers.STAGES.index(s) >= ledgers.STAGES.index("integration")
    ]
    if not ctx.exempt("stages") and not later:
        out.append(msg("no_stages"))

    surf = ledgers.surface(root)
    if not ctx.exempt("surface"):
        if surf is None:
            out.append(msg("no_surface"))
        elif surf["problems"]:
            out.append(msg("surface_invalid", why="; ".join(surf["problems"])))
        elif not [r for r in ctx.recs("run", entry="surface", change=change) if r.get("exit") == 0]:
            out.append(msg("surface_not_run", command=surf["command"]))

    templates = [p for p in (root / ".github").glob("*") if p.name.lower().startswith("pull_request_template")]
    # a body the parser could not read ($(cat file) arrives as SUBST) and a repository with its own template are left alone
    if body is not None and "SUBST" not in body and not templates and not ctx.exempt("pr_body"):
        for heading, words in (
            ("影響の範囲", "影響の範囲|Blast Radius|Impact"),
            ("検証", "検証|Verification|Test Plan"),
        ):
            # the command parser turns a newline inside the quoted body into " ; "
            if not re.search(rf"(^|;\s*)#+\s*({words})", body, re.M | re.I):
                out.append(msg("pr_body", heading=heading))
    return out


def protected(ctx, tool_input_text, approval_text=True):
    """1-11: nothing but the hymme tools touches the key or the log; nothing fakes an approval line."""
    out = []
    key = store.key_path()
    spots = [str(key.parent)] if key else []
    try:
        spots.append(str(store.root(ctx.cwd)))
    except store.NoRepo:
        pass
    spots.append(".git/hymme")
    for spot in spots:
        if spot in tool_input_text:
            out.append(msg("protected", path=spot))
            break
    if approval_text and APPROVAL.search(tool_input_text):
        out.append(msg("approval_text"))
    return out
