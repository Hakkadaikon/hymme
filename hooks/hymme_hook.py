#!/usr/bin/env python3
"""すべての hook の事象の入口。本体は ../agentloop/lib/hymme/hook.py。

PreToolUse、PostToolUse、PostToolUseFailure、SubagentStop、UserPromptSubmit から呼ばれる。stdin に hook の JSON。
python3 -I で動くので、ライブラリの場所はこのファイルの位置から決める。
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "agentloop", "lib"))

from hymme.hook import main  # noqa: E402

sys.exit(main())
