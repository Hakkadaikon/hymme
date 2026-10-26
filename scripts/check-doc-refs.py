#!/usr/bin/env python3
"""文書の参照の整合を検査する: `hymme:<name>` が実在の agent / 一覧に出るスキルを指すか、相対リンクが実在するか。

スキルや agent を改名・削除・一覧から隠したときの書き換え漏れを静的に止める。一覧から隠したスキル
(disable-model-invocation: true)は Skill ツールで呼べないので、`hymme:<隠したスキル>` と書くこと自体を誤りとする。
対象は README.md と agents/・skills/ の *.md と hooks/ のファイル。
使い方: check-doc-refs.py [repo-root]   (exit 0: 問題なし、1: 問題あり)
"""

import glob
import os
import re
import sys

MESSAGES = {
    "unknown": "{path}:{line}: hymme:{name} という agent / スキルは無い",
    "hidden": "{path}:{line}: hymme:{name} は一覧から隠したスキル。SKILL.md のパスで Read させる",
    "broken_link": "{path}:{line}: リンク先が無い: {target}",
}


def msg(code, **kw):
    """端末に出す文言をコードから引く(文言をこの表1か所に集める)。"""
    return MESSAGES.get(code, "未知のメッセージコード: " + code).format(**kw)


def frontmatter(path):
    with open(path, encoding="utf-8") as f:
        m = re.match(r"---\n(.*?)\n---", f.read(), re.S)
    return m.group(1) if m else ""


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    os.chdir(root)
    agents = {os.path.basename(p)[:-3] for p in glob.glob("agents/*.md")}
    skills, hidden = set(), set()
    for p in glob.glob("skills/*/SKILL.md"):
        name = os.path.basename(os.path.dirname(p))
        skills.add(name)
        if re.search(r"^disable-model-invocation:\s*true", frontmatter(p), re.M):
            hidden.add(name)
    files = [
        "README.md",
        *glob.glob("agents/*.md"),
        *glob.glob("skills/**/*.md", recursive=True),
        *glob.glob("hooks/*"),
    ]
    errors = []
    for path in files:
        with open(path, encoding="utf-8", errors="ignore") as f:
            lines = f.read().splitlines()
        for i, line in enumerate(lines, 1):
            for name in re.findall(r"hymme:([a-z0-9][a-z0-9-]*)", line):
                if name in hidden:
                    errors.append(msg("hidden", path=path, line=i, name=name))
                elif name not in agents and name not in skills:
                    errors.append(msg("unknown", path=path, line=i, name=name))
            if path.endswith(".md"):
                for target in re.findall(r"\]\(([^)#\s]+)(?:#[^)]*)?\)", line):
                    if "://" in target or target.startswith("mailto:"):
                        continue
                    if not os.path.exists(os.path.normpath(os.path.join(os.path.dirname(path), target))):
                        errors.append(msg("broken_link", path=path, line=i, target=target))
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
