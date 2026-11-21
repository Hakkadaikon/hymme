"""Readers for the ledgers a worker keeps under <repo>/tasks/ (all git-untracked, all Markdown)."""

import fnmatch
import hashlib
import re
import time
from pathlib import Path

STAGES = ["spec", "unit", "integration", "e2e", "trace", "ci"]  # earliest first
CLAIM_FIELDS = ("示すこと", "示さないこと", "破れたときの害")
ESCAPE_FIELDS = (
    "症状",
    "見つかった段",
    "拾えたはずの段",
    "抜けた理由",
    "前段に足したテスト",
    "テストのコマンド",
    "水平展開",
)
ESCAPE_CAUSES = (
    "要件の抜け",
    "モデルで捨てた領域",
    "手法の選び違い",
    "テストの書き漏れ",
    "検証の弱いテスト",
    "前段では原理的に拾えない",
)
SURFACE_SECTIONS = ("起動", "健全性の確認", "操作", "証跡", "後片付け")
# words that give away the method; a claims list is read by someone who does not know them
METHOD_WORDS = re.compile(r"TLA\+|\b(?:TLA|TLC|EARS|SMT|Z3|Lean|Inv|[SRT]-\d+|mutation)\b|不変条件|モデル検査")
# what a record closed without a new test still has to say
NO_TEST_CAUSES = ("要件の抜け", "モデルで捨てた領域", "前段では原理的に拾えない")


def placeholder(text):
    """Whether a template's <…> is still in the text (a bare < as in `a < b` is not one)."""
    return bool(re.search(r"<[^<>\n]*[^\s<>0-9=][^<>\n]*>", text))


def section(text, heading):
    """Lines under '## <heading>' up to the next '## '."""
    out, on = [], False
    for line in text.splitlines():
        if line.startswith("## "):
            on = line[3:].strip() == heading
            continue
        if on:
            out.append(line)
    return out


def read(path):
    try:
        return Path(path).read_text(encoding="utf-8")
    except OSError:
        return None


def sha(text):
    return hashlib.sha256(text.encode()).hexdigest()


def request_code(kind, text_hash):
    """The 8 hex digits a worker types to approve a request; the same on the tool side and the hook side."""
    return sha(f"{kind}:{text_hash}")[:8]


def exception_hash(check, until, reason):
    return sha(f"{check}|{until}|{reason}")


def claims_path(root, name):
    """The list a worker confirms before <name> is verified, wherever the verification lives."""
    for sub in ("loopeng", "fv"):
        p = Path(root) / "tasks" / sub / f"{name}.claims.md"
        if p.exists():
            return p
    return Path(root) / "tasks" / "loopeng" / f"{name}.claims.md"


def claims_problems(text):
    """Why a claims list cannot be shown to a worker yet ([] when it can)."""
    problems = []
    rows = [ln for ln in section(text, "実証する項目") if ln.startswith("|") and not re.match(r"\|\s*[-:]+", ln)]
    cells = [[c.strip() for c in ln.strip().strip("|").split("|")] for ln in rows]
    if len(cells) < 2:
        return ["「## 実証する項目」の表に行が無い"]
    header, body = cells[0], cells[1:]
    for field in ("要件", *CLAIM_FIELDS):
        if field not in header:
            problems.append(f"「## 実証する項目」の表に「{field}」の列が無い")
    if problems:
        return problems
    for row in body:
        row = row + [""] * (len(header) - len(row))
        for field in ("要件", *CLAIM_FIELDS):
            if not row[header.index(field)] or placeholder(row[header.index(field)]):
                problems.append(f"「{row[header.index('要件')] or '?'}」の「{field}」が空")
    for heading in ("有限にした範囲", "扱わない領域"):
        if not [ln for ln in section(text, heading) if ln.strip() and not placeholder(ln)]:
            problems.append(f"「## {heading}」が空(無ければ「無し: 理由」と書く)")
    leaked = sorted(set(METHOD_WORDS.findall(text)))
    if leaked:
        problems.append("手法の用語か管理番号がある: " + ", ".join(leaked))
    return problems


def verifiability_targets(root):
    """{name: [path, ...]} from the '## 対象' section of every tasks/verifiability/<name>.md."""
    out = {}
    for ledger in sorted((Path(root) / "tasks" / "verifiability").glob("*.md")):
        text = read(ledger) or ""
        paths = [m.group(1) for ln in section(text, "対象") for m in [re.match(r"- (\S+?)::\S+", ln)] if m]
        if paths:
            out[ledger.stem] = sorted(set(paths))
    return out


def log_spec(root, name):
    """The spec real logs are checked against for <name>: itself, unless its verifiability ledger names
    another with '実ログの spec: <Other>' (a spec that models lock steps cannot read a log with one line per command)."""
    m = re.search(
        r"^実ログの spec[:：]\s*(\w+)\s*$", read(Path(root) / "tasks" / "verifiability" / f"{name}.md") or "", re.M
    )
    return m.group(1) if m else name


def parity_commands(root):
    """{name: command prefix} from a '突き合わせ: <command>' line of a verifiability ledger."""
    out = {}
    for ledger in sorted((Path(root) / "tasks" / "verifiability").glob("*.md")):
        m = re.search(r"^突き合わせ[:：]\s*`?(.+?)`?\s*$", read(ledger) or "", re.M)
        if m:
            out[ledger.stem] = m.group(1)
    return out


def extract_problems(text):
    """Why an extraction ledger is not closed: unchecked IDs, gaps, or an open closing check."""
    problems = []
    body = "\n".join(section(text, "台帳"))
    if re.search(r"^\s*- \[ \] S-", body, re.M):
        problems.append("未チェック(- [ ] S-...)が残っている")
    nums = sorted({int(n) for n in re.findall(r"S-(\d+)", body)})
    if not nums:
        problems.append("S-ID が1つも無い")
    elif nums != list(range(nums[0], nums[-1] + 1)):
        problems.append(f"S-ID の連番に欠番がある(S-{nums[0]:03d}..S-{nums[-1]:03d})")
    closing = section(text, "閉じる前のチェック")
    if not closing:
        problems.append("「## 閉じる前のチェック」が無い")
    elif any(re.match(r"\s*- \[ \]", ln) for ln in closing):
        problems.append("「閉じる前のチェック」に未チェックが残っている")
    elif any(re.fullmatch(r"\s+- [^:：]+[:：]\s*", ln) for ln in closing):
        problems.append("「閉じる前のチェック」に空の行がある")
    return problems


def stages(root):
    """Declared stages: {'commands': [(stage, prefix)], 'paths': [(stage, glob)], 'none': reason or None}."""
    text = read(Path(root) / "tasks" / "stages.md")
    if text is None:
        return None
    decl = {"commands": [], "paths": [], "none": None}
    for ln in text.splitlines():
        m = re.match(r"- (\w+) (コマンド|パス)[:：]\s*`?(.+?)`?\s*$", ln)
        if m and m.group(1) in STAGES:
            decl["commands" if m.group(2) == "コマンド" else "paths"].append((m.group(1), m.group(3)))
        m = re.match(r"段なし[:：]\s*(\S.*)$", ln)
        if m:
            decl["none"] = m.group(1)
    return decl


def stage_of_command(decl, command):
    """The latest declared stage whose command prefix this command line starts with."""
    hits = [s for s, prefix in decl["commands"] if command.strip().startswith(prefix)]
    return max(hits, key=STAGES.index) if hits else None


def stage_of_path(decl, path):
    hits = [s for s, glob in decl["paths"] if fnmatch.fnmatch(path, glob)]
    return min(hits, key=STAGES.index) if hits else None


def fields(text):
    """'- 名前: 値' lines as a dict (the form of an escape record and of a surface definition)."""
    out = {}
    for ln in text.splitlines():
        m = re.match(r"- ([^:：]+)[:：]\s*(.*)$", ln)
        if m:
            out[m.group(1).strip()] = m.group(2).strip()
    return out


def escape_problems(text, decl):
    """Why an escape record cannot be closed yet, apart from running its test."""
    f = fields(text)
    needed = [
        k
        for k in ESCAPE_FIELDS
        if k not in ("前段に足したテスト", "テストのコマンド") or f.get("抜けた理由") not in NO_TEST_CAUSES
    ]
    problems = [f"「{k}」が空" for k in needed if not f.get(k) or placeholder(f[k])]
    if problems:
        return problems
    if f["抜けた理由"] not in ESCAPE_CAUSES:
        problems.append("「抜けた理由」は次のどれかにする: " + " / ".join(ESCAPE_CAUSES))
    for k in ("見つかった段", "拾えたはずの段"):
        if f[k] not in STAGES:
            problems.append(f"「{k}」は次のどれかにする: " + " / ".join(STAGES))
    if problems:
        return problems
    if STAGES.index(f["拾えたはずの段"]) >= STAGES.index(f["見つかった段"]):
        problems.append("「拾えたはずの段」が「見つかった段」より前でない")
    if f["抜けた理由"] not in NO_TEST_CAUSES:
        stage = stage_of_path(decl, f["前段に足したテスト"]) if decl else None
        if stage is None:
            problems.append(
                f"前段に足したテスト {f['前段に足したテスト']} が tasks/stages.md のどの段のパスにも当たらない"
            )
        elif STAGES.index(stage) >= STAGES.index(f["見つかった段"]):
            problems.append(f"前段に足したテストが {stage} の段にあり、見つかった段({f['見つかった段']})より前でない")
    return problems


def new_escape_id(root):
    """An id no escape record under this root has yet (two can be opened within one second)."""
    stamp, n = time.strftime("E%Y%m%d-%H%M%S"), 0
    while (Path(root) / "tasks" / "escapes" / f"{stamp}{'-' + str(n) if n else ''}.md").exists():
        n += 1
    return f"{stamp}{'-' + str(n) if n else ''}"


def surface(root):
    """The definition of how to run the real system: {'problems': [...], 'command': prefix or None}."""
    text = read(Path(root) / "tasks" / "surface.md")
    if text is None:
        return None

    def filled(lines):
        return [ln for ln in lines if ln.strip() and not placeholder(ln)]  # a template line left as it was is empty

    problems = [f"「## {h}」が空" for h in SURFACE_SECTIONS if not filled(section(text, h))]
    command = (filled([fields(text).get("確認のコマンド", "")]) or [None])[0]
    if not command:
        problems.append("「- 確認のコマンド: <実物を動かして確かめるコマンドの先頭>」が無い")
    if not filled([fields(text).get("検証と本番で違う値", "")]):
        problems.append("「- 検証と本番で違う値: <容量やタイムアウトなどの一覧。無ければ「無し: 理由」>」が無い")
    return {"problems": problems, "command": command.strip("`") if command else None}


def managed(root):
    """Whether this repository keeps hymme ledgers at all (a repository that keeps none is left alone)."""
    tasks = Path(root) / "tasks"
    return any(
        (tasks / d).exists() for d in ("loopeng", "fv", "verifiability", "test-design", "stages.md", "surface.md")
    )
