#!/usr/bin/env python3
"""台帳の「テスト対象:」の glob が対象ファイルを含むかを exit code で返す(0: 含む/対象指定なし、1: 含まない)。"""

import fnmatch
import re
import sys

ledger, rel = sys.argv[1], sys.argv[2]
values = [m.group(1) for m in map(re.compile(r"^テスト対象[:：](.*)").match, open(ledger, encoding="utf-8")) if m]
globs = [g for v in values if "<" not in v for g in v.split()]
sys.exit(0 if not globs or any(fnmatch.fnmatch(rel, g) for g in globs) else 1)
