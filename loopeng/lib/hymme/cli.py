"""hymme: the command a worker runs to ask for an approval, handle an escape record, or draw a state chart.

The command never signs anything. It checks what a machine can check and leaves a request or a
result behind; the hook that watches the command writes the signed record.
"""

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from . import chart, ledgers, store

MESSAGES = {
    "claims_missing": "{path} が無い。要件ごとに「示すこと」「示さないこと」「破れたときの害」を書く。",
    "claims_invalid": "{path} は作業者に見せられる形になっていない:\n{why}",
    "request": "申請を作りました。作業者に次の内容が表示されます。承認の入力は作業者だけができます。\n符号: {code}",
    "claims_ok": "{path} は作業者に見せられる形です。",
    "bad_check": "検査 {check} は例外で外せません。外せる検査: {known}",
    "bad_date": "--until は YYYY-MM-DD の形で、今日以降にします。",
    "escape_created": "欠陥の記録を作りました: {path}\n欄を埋めたら `hymme escape verify {id}` を実行します。",
    "escape_missing": "欠陥の記録 {path} が無い。",
    "escape_invalid": "欠陥の記録 {path} はまだ閉じられません:\n{why}",
    "red_expected": "足したテストが修正前のコード({base})で失敗しません(終了コード 0)。このテストは欠陥を拾えていません。\nコマンド: {command}",
    "green_expected": "足したテストが今のコードで通りません(終了コード {code})。\nコマンド: {command}\n{tail}",
    "repro_red": "再現のコマンドが修正前のコード({base})で失敗しません。再現になっていません。\nコマンド: {command}",
    "repro_green": "再現のコマンドが今のコードで通りません(終了コード {code})。直っていません。\nコマンド: {command}\n{tail}",
    "verified": "欠陥の記録 {id} の確認が通りました(修正前に失敗、修正後に成功)。",
    "needs_approval": "欠陥の記録 {id} の欄は埋まっています。この閉じ方には作業者の承認が要ります: {how}",
    "no_escapes": "欠陥の記録はありません。",
    "specs": "この変更が触れている検証の対象:",
    "no_specs": "この変更が触れている検証の対象はありません。",
    "no_repo": "git リポジトリの中で実行してください。",
}


def msg(code, /, **kw):
    """端末に出す文言をコードから引く(文言をこの表1か所に集める)。"""
    return MESSAGES.get(code, "未知のメッセージコード: " + code).format(**kw)


def fail(code, /, **kw):
    print(msg(code, **kw), file=sys.stderr)
    return 1


def request(kind, text_hash, **fields):
    """Leave a request for the worker; the hook shows it and records the answer."""
    code = ledgers.sha(f"{kind}:{text_hash}")[:8]
    base = store.root() / "pending"
    base.mkdir(parents=True, exist_ok=True)
    req = {"type": kind, "hash": text_hash, "code": code, "version": store.VERSION, **fields}
    (base / f"{code}.json").write_text(json.dumps(req, ensure_ascii=False), encoding="utf-8")
    print(msg("request", code=code))
    return 0


def claims(args):
    root = store.toplevel()
    path = ledgers.claims_path(root, args.name)
    text = ledgers.read(path)
    if text is None:
        return fail("claims_missing", path=path)
    problems = ledgers.claims_problems(text)
    if problems:
        return fail("claims_invalid", path=path, why="\n".join("- " + p for p in problems))
    if args.action == "check":
        print(msg("claims_ok", path=path))
        return 0
    return request("claims", ledgers.sha(text), name=args.name, path=str(path), text=text)


def exception(args):
    from . import checks  # the table of exemptable checks lives with the checks

    if args.check not in checks.EXEMPTABLE:
        return fail("bad_check", check=args.check, known=", ".join(sorted(checks.EXEMPTABLE)))
    try:
        ok = time.strptime(args.until, "%Y-%m-%d") and args.until >= time.strftime("%Y-%m-%d")
    except ValueError:
        ok = False
    if not ok:
        return fail("bad_date")
    return request("exception", ledgers.sha(f"{args.check}|{args.until}|{args.reason}"), check=args.check, until=args.until, reason=args.reason)


def escape_path(root, eid):
    return Path(root) / "tasks" / "escapes" / f"{eid}.md"


def run(command, cwd):
    out = subprocess.run(command, shell=True, cwd=cwd, capture_output=True, text=True, check=False)
    return out.returncode, "\n".join((out.stdout + out.stderr).strip().splitlines()[-12:])


def red_then_green(root, base, command, overlay, prepare):
    """(code before the fix, code now, tail of the output now): the command at `base` with `overlay` copied in, then here."""
    tmp = Path(tempfile.mkdtemp(prefix="hymme-escape-"))
    try:
        store.git("worktree", "add", "--detach", str(tmp / "w"), base, cwd=root)
        for rel in overlay:
            src, dst = Path(root) / rel, tmp / "w" / rel
            if src.is_file():
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst)
        if prepare:
            run(prepare, tmp / "w")
        before, _ = run(command, tmp / "w")
    finally:
        subprocess.run(["git", "worktree", "remove", "--force", str(tmp / "w")], cwd=root, capture_output=True, check=False)
        shutil.rmtree(tmp, ignore_errors=True)
    after, tail = run(command, root)
    return before, after, tail


def escape(args):
    root = store.toplevel()
    if args.action == "list":
        paths = sorted((Path(root) / "tasks" / "escapes").glob("E*.md"))
        print("\n".join(str(p) for p in paths) if paths else msg("no_escapes"))
        return 0
    if args.action == "stats":
        counts = {}
        for p in sorted((Path(root) / "tasks" / "escapes").glob("E*.md")):
            cause = ledgers.fields(p.read_text(encoding="utf-8")).get("抜けた理由") or "未記入"
            counts[cause] = counts.get(cause, 0) + 1
        for cause, n in sorted(counts.items(), key=lambda kv: -kv[1]):
            print(f"{n}\t{cause}" + ("\t(2回以上: 構造で防ぐ手段を review-feedback の手順で作る)" if n >= 2 else ""))
        return 0
    if args.action == "open":
        eid = ledgers.new_escape_id(root)
        path = escape_path(root, eid)
        path.parent.mkdir(parents=True, exist_ok=True)
        lines = [f"# 欠陥の記録 {eid}", "", f"- 症状: {args.symptom}", f"- 見つかった段: {args.stage}"]
        lines += [f"- {k}: " for k in ledgers.ESCAPE_FIELDS if k not in ("症状", "見つかった段")]
        lines += ["- 再現のコマンド: ", "- 修正前のコミット: ", "- 準備のコマンド: ", ""]
        path.write_text("\n".join(lines), encoding="utf-8")
        print(msg("escape_created", path=path, id=eid))
        return 0

    path = escape_path(root, args.id)
    text = ledgers.read(path)
    if text is None:
        return fail("escape_missing", path=path)
    problems = ledgers.escape_problems(text, ledgers.stages(root))
    if problems:
        return fail("escape_invalid", path=path, why="\n".join("- " + p for p in problems))
    f = ledgers.fields(text)
    if args.action == "unreachable":
        return request("unreachable", ledgers.sha(text), id=args.id, path=str(path), reason=args.reason)
    if f["抜けた理由"] == "前段では原理的に拾えない":
        print(msg("needs_approval", id=args.id, how=f"`hymme escape unreachable {args.id} --reason <理由>` で申請する"))
        return 0
    if f["抜けた理由"] in ("要件の抜け", "モデルで捨てた領域"):
        print(msg("needs_approval", id=args.id, how="要件と一覧を直し、`hymme claims request <名前>` で承認を取り直す"))
        return 0
    base = f.get("修正前のコミット") or store.merge_base(root)
    before, after, tail = red_then_green(root, base, f["テストのコマンド"], [f["前段に足したテスト"]], f.get("準備のコマンド"))
    if before == 0:
        return fail("red_expected", base=base[:8], command=f["テストのコマンド"])
    if after != 0:
        return fail("green_expected", code=after, command=f["テストのコマンド"], tail=tail)
    if f.get("再現のコマンド"):
        before, after, tail = red_then_green(root, base, f["再現のコマンド"], [], f.get("準備のコマンド"))
        if before == 0:
            return fail("repro_red", base=base[:8], command=f["再現のコマンド"])
        if after != 0:
            return fail("repro_green", code=after, command=f["再現のコマンド"], tail=tail)
    print(msg("verified", id=args.id))
    return 0


def specs(_args):
    root = store.toplevel()
    changed = store.changed_files(root)
    hits = {n: sorted(set(p) & changed) for n, p in ledgers.verifiability_targets(root).items() if set(p) & changed}
    if not hits:
        print(msg("no_specs"))
        return 0
    print(msg("specs"))
    for name, paths in sorted(hits.items()):
        print(f"{name}\t{', '.join(paths)}")
    return 0


def draw(args):
    root = store.toplevel()
    if args.action == "request":
        path = Path(root) / "tasks" / "loopeng" / f"{args.name}.chart.md"
        text = ledgers.read(path)
        if text is None:
            return fail("claims_missing", path=path)
        return request("chart", ledgers.sha(text), name=args.name, path=str(path), text=text)
    return chart.main(Path(root) / "tasks" / "loopeng", args.name)


def main(argv=None):
    p = argparse.ArgumentParser(prog="hymme")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("claims", help="検証の前に作業者へ確かめる一覧")
    c.add_argument("action", choices=["check", "request"])
    c.add_argument("name")
    c.set_defaults(fn=claims)
    x = sub.add_parser("exception", help="検査を期限つきで外す申請")
    x.add_argument("action", choices=["request"])
    x.add_argument("check")
    x.add_argument("--until", required=True)
    x.add_argument("--reason", required=True)
    x.set_defaults(fn=exception)
    e = sub.add_parser("escape", help="後段で見つかった欠陥の記録")
    e.add_argument("action", choices=["open", "verify", "unreachable", "list", "stats"])
    e.add_argument("id", nargs="?")
    e.add_argument("--stage", choices=ledgers.STAGES, default="e2e")
    e.add_argument("--symptom", default="")
    e.add_argument("--reason", default="")
    e.set_defaults(fn=escape)
    s = sub.add_parser("specs", help="この変更が触れている検証の対象")
    s.set_defaults(fn=specs)
    d = sub.add_parser("chart", help="状態の図と、規則ごとの結果")
    d.add_argument("action", choices=["draw", "request"])
    d.add_argument("name")
    d.set_defaults(fn=draw)
    args = p.parse_args(argv)
    try:
        return args.fn(args)
    except store.NoRepo:
        return fail("no_repo")


if __name__ == "__main__":
    sys.exit(main())
