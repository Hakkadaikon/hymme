#!/usr/bin/env python3
"""品質ゲートの一部: msg() で引くメッセージコードが、そのファイルの対応表にすべてあるかを検査する。

Python は MESSAGES のキーと msg() に渡すコード、シェルは msg() の case ラベルと msg に渡すコードを突き合わせる。
対応表に無いコードは実行時に「未知のメッセージコード」と表示されるだけで落ちないので、ここで静的に止める。
変数で渡すコード(msg "$code")は静的に決まらないので見ない(実行時の「未知のメッセージコード」表示に任せる)。
使い方: check-messages.py <file>...   (exit 0: 全部ある、1: 足りないコードがある)
"""

import re
import sys

MESSAGES = {
    "missing": "{path}: 対応表に無いメッセージコード: {codes}",
}


def msg(code, **kw):
    """端末に出す文言をコードから引く(文言をこの表1か所に集める)。"""
    return MESSAGES.get(code, "未知のメッセージコード: " + code).format(**kw)


def defined_and_used(path, text):
    if path.endswith(".py"):
        table = re.search(r"^MESSAGES = \{(.*?)^\}", text, re.M | re.S)
        defined = set(re.findall(r'^\s+["\'](\w+)["\']:', table.group(1), re.M)) if table else set()
        used = set(re.findall(r"""\bmsg\(\s*(?:code\s*=\s*)?["'](\w+)["']""", text))
    else:
        # msg() {, msg () {, function msg {: the table is the case … esac that follows (one-line bodies too)
        start = re.search(r"(?:^|[;{\s])(?:function\s+msg\b|msg\s*\(\s*\))\s*\{", text)
        end = text.find("esac", start.end()) if start else -1
        body = text[start.end() : end] if start and end > 0 else ""
        # a label starts a line, or follows ;; or "in" (a word followed by ")" inside a message is not one)
        labels = re.findall(r"(?:^\s*|;;\s*|\bin\s+)\(?((?:[\"']?\w+[\"']?\s*\|\s*)*[\"']?\w+[\"']?)\s*\)", body, re.M)
        defined = {lab.strip(" \"'") for group in labels for lab in group.split("|")}
        used = set(re.findall(r"""(?:^|[\s;&|(`])msg\s+["']?([a-z_]\w*)\b""", text, re.M))
    return defined, used


def main():
    failed = False
    for path in sys.argv[1:]:
        text = open(path, encoding="utf-8").read()
        if "msg" not in text:
            continue
        defined, used = defined_and_used(path, text)
        if not defined and not used:
            continue
        missing = sorted(used - defined)
        if missing:
            print(msg("missing", path=path, codes=", ".join(missing)))
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
