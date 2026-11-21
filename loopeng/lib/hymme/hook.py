"""One entry point for every hook event: python3 -I hooks/hymme_hook.py < payload.

PreToolUse stops a tool call (exit 2, reason on stderr). PostToolUse, PostToolUseFailure, SubagentStop
and UserPromptSubmit write the signed records the checks read: a worker cannot produce those events
by typing into a file, which is what makes a record worth more than a ticked box.
"""

import json
import os
import re
import sys
import time
from pathlib import Path

from . import checks, ledgers, store
from .cmdparse import Gate

MESSAGES = {
    "no_key": "hymme: 署名の鍵を置く場所(CLAUDE_PLUGIN_DATA)が hook に渡っていない。記録を確かめられないので止める。"
    "プラグインとして読み込まれているかを確かめる。",
    "show_claims": "【作業者の確認】{name} について、検証で実証する項目です。内容が正しければ、次の1行だけを入力してください: 承認 {code}\n"
    "(一覧のファイル: {path})\n\n{text}",
    "show_chart": "【作業者の確認】{name} の検査の結果と状態の図です。振る舞いが意図どおりなら、次の1行だけを入力してください: 承認 {code}\n"
    "(ファイル: {path})\n\n{text}",
    "show_exception": "【作業者の確認】検査「{check}」を {until} まで外す申請です。理由: {reason}\n認めるなら、次の1行だけを入力してください: 承認 {code}",
    "show_unreachable": "【作業者の確認】欠陥の記録 {id} を「前段では原理的に拾えない」として閉じる申請です。理由: {reason}\n"
    "認めるなら、次の1行だけを入力してください: 承認 {code}",
    "approved": "hymme: 承認を記録しました({what})。",
    "approve_unknown": "hymme: 符号 {code} に当たる申請がありません。申請をやり直してください。",
    "approve_changed": "hymme: 申請のあとに内容が変わっています。申請をやり直してください({what})。",
    "approve_version": "hymme: 道具(バージョン {tool})と hook(バージョン {hook})が食い違っています。両方を同じバージョンに更新してください。",
    "escape_opened": "hymme: {stage} の段のコマンドが失敗したので、欠陥の記録 {id} を開きました({path})。"
    "拾えたはずの前の段にテストを足し、`hymme escape verify {id}` を通すまで、変更は統合できません。",
    "path_tampered": "hymme: コマンドの中で PATH を変えているので、hymme の道具の結果は記録しません。PATH を変えずに実行してください。",
}

RULES = [
    re.compile(r"Invariant (\S+) is violated"),
    re.compile(r"Temporal property (\S+) was violated"),
    re.compile(r"(Temporal properties were violated)"),
    re.compile(r"(Deadlock reached)"),
    re.compile(r"不一致: (\d+ 行目)"),
    re.compile(r"性質 (\S+)[^\n]*(?:反例|壊した版)"),
    re.compile(r"^(\S+::\S+ \S+)[:：]", re.M),
]
APPROVE_LINE = re.compile(r"承認 ([0-9a-f]{8})")
PR_TOOL = re.compile(r"create_(pull|merge)_request", re.I)
MAX_EXCEPTION_DAYS = 90


def msg(code, /, **kw):
    """端末に出す文言をコードから引く(文言をこの表1か所に集める)。"""
    return MESSAGES.get(code, "未知のメッセージコード: " + code).format(**kw)


def emit(system=None, context=None, event=None):
    out = {}
    if system:
        out["systemMessage"] = system
    if context and event:
        out["hookSpecificOutput"] = {"hookEventName": event, "additionalContext": context}
    if out:
        print(json.dumps(out, ensure_ascii=False))


def output_text(payload):
    resp = payload.get("tool_response")
    if isinstance(resp, dict):
        return f"{resp.get('stdout', '')}\n{resp.get('stderr', '')}"
    return str(payload.get("error") or resp or "")


def exit_code(payload):
    if payload.get("hook_event_name") != "PostToolUseFailure":
        return 0
    m = re.match(r"Exit code (\d+)", str(payload.get("error", "")))
    return int(m.group(1)) if m else 1


def pr_body(args):
    """The body a `gh pr create` / `glab mr create` passes on the command line (None when it passes none)."""
    for i, a in enumerate(args):
        if a in ("--body", "-b", "--description", "-d") and i + 1 < len(args):
            return args[i + 1]
        if a in ("--body-file", "-F") and i + 1 < len(args):
            return ledgers.read(args[i + 1])
        for flag in ("--body=", "--description="):
            if a.startswith(flag):
                return a[len(flag) :]
    return None


def leaves(gate, ctx):
    """How a command line would carry a change off the branch: ('pr'|'merge'|'push', body) or None."""
    for verb, args, _cwd, _env in gate.commands:
        words = [a for a in args if not a.startswith("-")]
        if verb == "gh" and words[:2] == ["pr", "create"] or verb == "glab" and words[:2] == ["mr", "create"]:
            return "pr", pr_body(args)
        if verb == "gh" and words[:1] == ["api"] and any(re.search(r"/pulls/?$", a) for a in words):
            if any(a in ("POST", "-f", "-F", "--field", "--raw-field", "--input") for a in args):
                return "pr", None
        if verb == "git":
            rest = list(args)
            while rest and rest[0].startswith("-"):  # git's own options come before the subcommand
                rest = rest[2:] if rest[0] in ("-C", "-c", "--git-dir", "--work-tree") else rest[1:]
            sub = rest[0] if rest else None
            if sub == "merge" and "--abort" not in args and on_default_branch(ctx.cwd):
                return "merge", None
            if sub == "push" and ctx.recs("integrated", branch=current_branch(ctx.cwd)):
                return "push", None
    return None


def current_branch(cwd):
    return store.branch(cwd)


def on_default_branch(cwd):
    try:
        return store.git("rev-parse", "HEAD", cwd=cwd) == store.default_base(cwd)
    except store.NoRepo:
        return False


def pre_tool(payload, key):
    cwd = payload.get("cwd") or os.getcwd()
    tool, tool_input = payload.get("tool_name", ""), payload.get("tool_input", {})
    ctx = checks.Ctx(cwd, key)
    if tool in ("Write", "Edit", "NotebookEdit", "Read"):
        # a file's content may mention the store (this plugin's own source does); only its path is checked
        reasons = checks.protected(
            ctx, " ".join(str(tool_input.get(k, "")) for k in ("file_path", "notebook_path")), False
        )
    else:
        reasons = checks.protected(ctx, json.dumps(tool_input, ensure_ascii=False))
    if PR_TOOL.search(tool):
        reasons += need_key(key) or checks.integration(ctx, tool_input.get("body"))
    if tool == "Bash":
        gate = Gate()
        gate.parse(tool_input.get("command", ""), cwd, {})
        ctx.gate, ctx.command = gate, tool_input.get("command", "")
        if gate.entries():
            reasons += need_key(key) or (
                checks.extract(ctx) + checks.claims(ctx) + checks.review(ctx) + checks.premise(ctx)
            )
        leave = leaves(gate, ctx)
        if leave:
            reasons += need_key(key) or checks.integration(ctx, leave[1])
    if reasons:
        print("\n".join(dict.fromkeys(reasons)), file=sys.stderr)
        return 2
    return 0


def need_key(key):
    return [] if key else [msg("no_key")]


def trace_label(args):
    logs = [a for a in args if a.endswith(".jsonl")]
    m = re.search(r"\.(normal|load|fault|broken)\.jsonl$", logs[0]) if logs else None
    return m.group(1) if m else None


def rule_of(text):
    for pattern in RULES:
        m = pattern.search(text)
        if m:
            return m.group(1)
    return None


def input_hashes(root, name):
    base = Path(root) / "tasks"
    files = [base / "loopeng" / f"{name}{ext}" for ext in (".tla", ".cfg", ".smt.py")]
    return {str(p.relative_to(root)): store.sha256_file(p) for p in files if p.exists()}


def post_tool(payload, key):
    """Notarize what a Bash command did: verification runs, stage runs, and the hymme tools' own results."""
    if payload.get("tool_name") != "Bash" or key is None:
        return 0
    cwd = payload.get("cwd") or os.getcwd()
    command = payload.get("tool_input", {}).get("command", "")
    gate = Gate()
    gate.parse(command, cwd, {})
    code, text = exit_code(payload), output_text(payload)
    try:
        root = store.toplevel(cwd)
    except store.NoRepo:
        return 0
    ctx = checks.Ctx(cwd, key, gate, command)

    for eroot, name, kind in gate.entries():
        rec = {"name": name, "entry": kind, "exit": code, "change": ctx.change(), "inputs": input_hashes(eroot, name)}
        if code != 0:
            rec["rule"] = rule_of(text) or f"exit-{code}"
        if "unverified" in text:
            rec["inconclusive"] = True
        if kind == "trace_check":
            args, at = next(((a, c) for v, a, c, _e in gate.commands if v == "trace_check.py"), ([], cwd))
            rec["label"] = trace_label(args)
            rec["log"] = next((store.sha256_file(Path(at) / a) for a in args if a.endswith(".jsonl")), None)
        store.append("run", rec, cwd, key)

    for verb, args, _c, _e in gate.commands:
        if verb == "verifiability.py":
            ledger = next((a for a in args if a.endswith(".md")), "")
            store.append(
                "run", {"name": Path(ledger).stem, "entry": "verifiability", "exit": code, "change": ctx.change()}, cwd, key
            )

    for name, prefix in ledgers.parity_commands(root).items():
        if command.strip().startswith(prefix):
            store.append("run", {"name": name, "entry": "parity", "exit": code, "change": ctx.change()}, cwd, key)

    surf = ledgers.surface(root)
    if surf and surf["command"] and command.strip().startswith(surf["command"]):
        store.append("run", {"name": "surface", "entry": "surface", "exit": code, "change": ctx.change()}, cwd, key)

    decl = ledgers.stages(root)
    stage = ledgers.stage_of_command(decl, command) if decl else None
    if stage:
        store.append("stage-run", {"stage": stage, "exit": code, "change": ctx.change(), "command": command[:200]}, cwd, key)
        if code != 0 and ledgers.STAGES.index(stage) >= ledgers.STAGES.index("integration"):
            open_escape(ctx, root, decl, stage, command, text)

    if leaves(gate, ctx) and code == 0:
        store.append("integrated", {"branch": current_branch(cwd), "change": ctx.change()}, cwd, key)

    if any(v == "hymme" for v, _a, _c, _e in gate.commands):
        if any("PATH" in e for _v, _a, _c, e in gate.commands) or re.search(r"\bPATH=", command):
            emit(system=msg("path_tampered"))
        elif code == 0:
            hymme_results(ctx, root, gate)
    return 0


def open_escape(ctx, root, decl, stage, command, text):
    """3-04, 3-05: a later-stage command failed and this branch did not touch that stage's tests."""
    changed = store.changed_files(ctx.cwd)
    if any(ledgers.stage_of_path(decl, p) == stage for p in changed):
        return  # tests of this stage are being written on this branch; a red run is expected
    if checks.open_escapes(ctx):
        return  # one open record already holds the change back
    eid = ledgers.new_escape_id(root)
    path = root / "tasks" / "escapes" / f"{eid}.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    tail = "\n".join(text.strip().splitlines()[-15:])
    lines = [f"# 欠陥の記録 {eid}", "", f"- 失敗したコマンド: {command[:200]}", f"- 見つかった段: {stage}"]
    lines += [f"- {k}: " for k in ledgers.ESCAPE_FIELDS if k != "見つかった段"]
    lines += ["- 再現のコマンド: ", "- 修正前のコミット: ", "", "## 失敗の出力", "", "```", tail, "```", ""]
    path.write_text("\n".join(lines), encoding="utf-8")
    opened = {"id": eid, "stage": stage, "branch": store.branch(ctx.cwd)}
    store.append("escape-open", opened, ctx.cwd, ctx.key)
    emit(system=msg("escape_opened", stage=stage, id=eid, path=path))


def pending(cwd, code):
    text = ledgers.read(store.root(cwd) / "pending" / f"{code}.json")
    return json.loads(text) if text else None


def option(args, flag):
    for i, a in enumerate(args):
        if a == flag and i + 1 < len(args):
            return args[i + 1]
        if a.startswith(flag + "="):
            return a[len(flag) + 1 :]
    return ""


def requested_code(root, words, args):
    """The code of the request this very command made, worked out from its arguments (never 'the newest file')."""
    target = words[2] if len(words) > 2 else ""
    if words[:2] == ["claims", "request"]:
        return ledgers.request_code("claims", ledgers.sha(ledgers.read(ledgers.claims_path(root, target)) or ""))
    if words[:2] == ["chart", "request"]:
        text = ledgers.read(Path(root) / "tasks" / "loopeng" / f"{target}.chart.md") or ""
        return ledgers.request_code("chart", ledgers.sha(text))
    if words[:2] == ["escape", "unreachable"]:
        text = ledgers.read(Path(root) / "tasks" / "escapes" / f"{target}.md") or ""
        return ledgers.request_code("unreachable", ledgers.sha(text))
    digest = ledgers.exception_hash(target, option(args, "--until"), option(args, "--reason"))
    return ledgers.request_code("exception", digest)


def hymme_results(ctx, root, gate):
    """Turn what a hymme command left behind into signed records or a message to the worker."""
    for verb, args, _c, _e in gate.commands:
        if verb != "hymme":
            continue
        words = [a for a in args if not a.startswith("-")]
        if words[:1] == ["capture"] and len(words) > 1:
            store.append("capture", {"log": store.sha256_file(Path(_c) / words[1]), "path": words[1]}, ctx.cwd, ctx.key)
        elif words[:2] in (
            ["claims", "request"],
            ["exception", "request"],
            ["escape", "unreachable"],
            ["chart", "request"],
        ):
            req = pending(ctx.cwd, requested_code(root, words, args))
            if req:
                show = {
                    "claims": "show_claims",
                    "exception": "show_exception",
                    "unreachable": "show_unreachable",
                    "chart": "show_chart",
                }
                emit(system=msg(show[req["type"]], **req))
        elif words[:2] == ["escape", "open"]:
            for path in sorted((root / "tasks" / "escapes").glob("E*.md")):
                if not ctx.recs("escape-open", id=path.stem):
                    stage = ledgers.fields(path.read_text()).get("見つかった段", "")
                    opened = {"id": path.stem, "stage": stage, "branch": store.branch(ctx.cwd)}
                    store.append("escape-open", opened, ctx.cwd, ctx.key)
        elif words[:2] == ["escape", "verify"] and len(words) > 2:
            text = ledgers.read(root / "tasks" / "escapes" / f"{words[2]}.md") or ""
            cause = ledgers.fields(text).get("抜けた理由")
            if cause == "前段では原理的に拾えない":
                if not ctx.recs("approval", type="unreachable", id=words[2], hash=ledgers.sha(text)):
                    continue  # closing this way needs the worker's approval, verify alone does not close it
            elif cause in ("要件の抜け", "モデルで捨てた領域"):
                opened = max((r["ts"] for r in ctx.recs("escape-open", id=words[2])), default=0)
                if not any(r["ts"] > opened for r in ctx.recs("approval", type="claims")):
                    continue  # the requirement was wrong: the worker approves the corrected list first
            store.append(
                "escape-closed", {"id": words[2], "change": ctx.change(), "hash": ledgers.sha(text)}, ctx.cwd, ctx.key
            )


def subagent_stop(payload, key):
    """1-10, 1-09: a reviewer's verdict is recorded from its last message when it stops."""
    if key is None:
        return 0
    cwd = payload.get("cwd") or os.getcwd()
    agent, text = str(payload.get("agent_type", "")), str(payload.get("last_assistant_message", ""))
    try:
        root = store.toplevel(cwd)
    except store.NoRepo:
        return 0
    if agent.endswith("verification-reviewer"):
        for verdict, target, name in re.findall(r"^判定: (合格|不合格) 対象=(\S+) 名前=(\S+)\s*$", text, re.M):
            rec = {"target": target, "name": name, "verdict": "pass" if verdict == "合格" else "fail"}
            if target == "verifiability":
                paths = ledgers.verifiability_targets(root).get(name, [])
                rec["ledger"] = store.sha256_file(root / "tasks" / "verifiability" / f"{name}.md")
                rec["files"] = checks.target_hashes(root, paths)
            store.append("review", rec, cwd, key)
    elif agent.endswith("diff-reviewer"):
        must = re.search(r"^must:\s*(\d+)\s*$", text, re.M)
        lenses = re.search(r"^lenses:\s*(.+?)\s*$", text, re.M)
        if must and lenses:
            claim = re.search(r"^claim_only:\s*(\d+)\s*$", text, re.M)
            rec = {"target": "diff", "change": store.change_id(cwd) or "none", "must": int(must.group(1))}
            rec.update(lenses=",".join(sorted(x.strip() for x in lenses.group(1).split(","))))
            rec["claim_only"] = int(claim.group(1)) if claim else 0
            store.append("review", rec, cwd, key)
    return 0


def user_prompt(payload, key):
    """2-07: an approval is the worker's whole input being `承認 <code>`; nothing else records one."""
    m = APPROVE_LINE.fullmatch(str(payload.get("prompt", "")).strip())
    if not m or key is None:
        return 0
    cwd, code = payload.get("cwd") or os.getcwd(), m.group(1)
    try:
        req = pending(cwd, code)
    except (store.NoRepo, ValueError):
        req = None
    event = "UserPromptSubmit"
    if not req:
        emit(system=msg("approve_unknown", code=code), context=msg("approve_unknown", code=code), event=event)
        return 0
    if req.get("version") != store.VERSION:
        text = msg("approve_version", tool=req.get("version"), hook=store.VERSION)
        emit(system=text, context=text, event=event)
        return 0
    kind = req["type"]
    if kind in ("claims", "unreachable", "chart"):
        if ledgers.sha(ledgers.read(req["path"]) or "") != req["hash"]:
            text = msg("approve_changed", what=req["path"])
            emit(system=text, context=text, event=event)
            return 0
        fields = {
            "type": kind,
            "hash": req["hash"],
            **({"id": req["id"]} if kind == "unreachable" else {"name": req["name"]}),
        }
        store.append("approval", fields, cwd, key)
        label = {"claims": "一覧", "chart": "状態の図", "unreachable": "閉じ方"}[kind]
        what = f"{req.get('name') or req.get('id')} の{label}"
    else:
        limit = time.strftime("%Y-%m-%d", time.localtime(time.time() + MAX_EXCEPTION_DAYS * 86400))
        until = min(req["until"], limit)
        store.append("exception", {"check": req["check"], "until": until, "reason": req["reason"]}, cwd, key)
        what = f"検査 {req['check']} の例外、{until} まで"
    emit(system=msg("approved", what=what), context=msg("approved", what=what), event=event)
    return 0


def main(stdin=None):
    try:
        payload = json.load(stdin or sys.stdin)
    except ValueError:
        return 0
    event = payload.get("hook_event_name")
    key = store.load_key(create=True)
    if event == "PreToolUse":
        return pre_tool(payload, key)
    if event in ("PostToolUse", "PostToolUseFailure"):
        return post_tool(payload, key)
    if event == "SubagentStop":
        return subagent_stop(payload, key)
    if event == "UserPromptSubmit":
        return user_prompt(payload, key)
    return 0
