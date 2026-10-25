#!/usr/bin/env python3
"""品質ゲートの一部: msg() で引くメッセージコードが、そのファイルの対応表にすべてあるかを検査する。

Python は MESSAGES のキーと msg() に渡すコード、シェルは msg() の case ラベルと msg に渡すコードを突き合わせる。
対応表に無いコードは実行時に「未知のメッセージコード」と表示されるだけで落ちないので、ここで静的に止める。
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
        defined = set(re.findall(r'^\s+"(\w+)":', table.group(1), re.M)) if table else set()
        used = set(re.findall(r'\bmsg\(\s*"(\w+)"', text))
    else:
        body = re.search(r"^\s*msg\(\) *\{.*?^\s*\}", text, re.M | re.S)
        defined = set(re.findall(r"^\s*([\w|]+)\)", body.group(0), re.M)) if body else set()
        defined = {c for d in defined for c in d.split("|")}
        used = set(re.findall(r"(?:^|[\s;&|(\"$])msg\s+([a-z_][\w]*)", text, re.M))
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
