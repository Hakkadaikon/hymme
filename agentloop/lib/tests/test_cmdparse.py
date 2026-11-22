"""Tests for the command parser: where an entry point is found, and where it is refused as unreadable."""

import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from hymme import cmdparse  # noqa: E402
from hymme.cmdparse import Gate  # noqa: E402


def parse(command, cwd="/r"):
    gate = Gate()
    gate.parse(command, cwd, {})
    return gate


class EntryTest(unittest.TestCase):
    def found(self, command, cwd="/r"):
        return parse(command, cwd).entries()

    def test_the_shell_gate_looks_for_the_same_loop_commands(self):
        import re

        gate = (Path(__file__).resolve().parents[3] / "hooks" / "verifiability-gate.sh").read_text(encoding="utf-8")
        pattern = re.search(r"grep -qE '([^']+)'", gate).group(1)
        for name in cmdparse.LOOPS:
            self.assertRegex(name + " SPEC=Cart", pattern)
        self.assertEqual(sorted(cmdparse.OLD_LOOPS), ["loop-inner", "loop-middle", "loop-outer"])
        self.assertNotRegex("loop-other SPEC=Cart", cmdparse.LOOP)  # only the three names are entries

    def test_wrappers_are_peeled(self):
        want = [("/r", "Cart", "agentloop-middle")]
        for command in (
            "agentloop-middle SPEC=Cart",
            "env A=1 agentloop-middle SPEC=Cart",
            "SPEC=Cart agentloop-middle",
            "export SPEC=Cart; agentloop-middle",
            "timeout -k 5 60 agentloop-middle SPEC=Cart",
            "nice -n 5 agentloop-middle SPEC=Cart",
            "sudo -u me agentloop-middle SPEC=Cart",
            "nix develop -c agentloop-middle SPEC=Cart",
            "bash -c 'agentloop-middle SPEC=Cart'",
            "bash -euo pipefail -c 'agentloop-middle SPEC=Cart'",
            "bash <<< 'agentloop-middle SPEC=Cart'",
            "true && { agentloop-middle SPEC=Cart; }",
            "if true; then agentloop-middle SPEC=Cart; fi",
            "echo $(agentloop-middle SPEC=Cart)",
            "echo `agentloop-middle SPEC=Cart`",
            "agentloop-middle SPEC=Cart 2>&1 > out.txt",
            "2> err.txt agentloop-middle SPEC=Cart",
            "python3 -W ignore -m venv x; agentloop-middle SPEC=Cart",
        ):
            self.assertEqual(self.found(command), want, command)

    def test_the_default_spec_name_and_a_make_directory(self):
        self.assertEqual(self.found("agentloop-outer"), [("/r", "Spec", "agentloop-outer")])
        self.assertEqual(
            self.found("make -C tasks/loopeng -f M agentloop-middle SPEC=A"), [("/r", "A", "agentloop-middle")]
        )
        self.assertEqual(self.found("make -Ctasks/loopeng agentloop-middle SPEC=A"), [("/r", "A", "agentloop-middle")])
        self.assertEqual(
            self.found("make --directory=tasks/loopeng agentloop-middle SPEC=A"), [("/r", "A", "agentloop-middle")]
        )
        self.assertEqual(self.found("env -C tasks/loopeng agentloop-middle SPEC=A"), [("/r", "A", "agentloop-middle")])
        self.assertEqual(self.found("env -u X agentloop-middle SPEC=A"), [("/r", "A", "agentloop-middle")])

    def test_oracles_take_the_name_from_their_file(self):
        self.assertEqual(self.found("smt_oracle.py tasks/loopeng/Rule.smt.py"), [("/r", "Rule", "smt_oracle")])
        self.assertEqual(
            self.found("python3 /x/smt_oracle.py --timeout 5 /p/tasks/loopeng/Rule.smt.py"),
            [("/p", "Rule", "smt_oracle")],
        )
        self.assertEqual(
            self.found("trace_check.py --all tasks/loopeng/A.tla run.jsonl --cfg x.cfg"), [("/r", "A", "trace_check")]
        )
        self.assertEqual(self.found("trace_check.py --cfg x.cfg"), [])

    def test_lake_build_is_found_by_its_directory(self):
        self.assertEqual(self.found("cd tasks/fv/Sort && lake build"), [("/r", "Sort", "lake")])
        self.assertEqual(self.found("lake -d tasks/fv/Sort build"), [("/r", "Sort", "lake")])
        self.assertEqual(self.found("lake --dir=tasks/fv/Sort build"), [("/r", "Sort", "lake")])
        self.assertEqual(self.found("pushd tasks/fv/Sort; lake build"), [("/r", "Sort", "lake")])
        self.assertEqual(self.found("lake build"), [])
        self.assertEqual(self.found("cd $HOME/other && lake build", cwd="/nonexistent"), [])

    def test_a_mention_is_not_a_run(self):
        for command in (
            "git commit -m 'run agentloop-middle SPEC=Cart and lake build'",
            "cat <<'EOF'\nagentloop-middle SPEC=Cart\nEOF",
            "echo 'trace_check.py a.tla'",
            "python3 -m unittest",
            "python3 -c 'print(1)'",
            "echo hi | python3",
            "echo hi | bash",
            "xargs ls",
        ):
            self.assertEqual((self.found(command), parse(command).blocks()), ([], []), command)

    def test_a_heredoc_a_shell_reads_is_parsed(self):
        self.assertEqual(
            self.found("bash <<EOF\nagentloop-middle SPEC=Cart\nEOF"), [("/r", "Cart", "agentloop-middle")]
        )
        self.assertEqual(
            self.found("cat <<EOF | sh\nagentloop-middle SPEC=Cart\nEOF"), [("/r", "Cart", "agentloop-middle")]
        )
        self.assertEqual(
            self.found("cat <<EOF\n$(agentloop-middle SPEC=Cart)\nEOF"), [("/r", "Cart", "agentloop-middle")]
        )


class BlockTest(unittest.TestCase):
    def blocked(self, command, cwd="/r"):
        return "\n".join(parse(command, cwd).blocks())

    def test_an_entry_hidden_where_it_cannot_be_read_is_refused(self):
        for command, why in (
            ("python3 <<EOF\nimport os; os.system('agentloop-middle SPEC=Cart')\nEOF", "heredoc"),
            ("python3 -c \"import os; os.system('agentloop-middle SPEC=Cart')\"", "python3 -c"),
            ("echo 'agentloop-middle SPEC=Cart' | python3", "標準入力"),
            ("echo 'agentloop-middle SPEC=Cart' | python3 -", "標準入力"),
            ("echo 'agentloop-middle SPEC=Cart' | bash", "標準入力"),
            ("echo 'agentloop-middle SPEC=Cart' | tee x | sh -s", "標準入力"),
            ("eval 'agentloop-middle SPEC=Cart'", "eval"),
            ("echo Cart | xargs -I{} agentloop-middle SPEC={}", "xargs"),
            ("agentloop-middle SPEC='Cart", "クォート"),
        ):
            self.assertIn(why, self.blocked(command), command)

    def test_a_name_that_is_not_fixed_or_not_plain_is_refused(self):
        self.assertIn("変数", self.blocked("agentloop-middle SPEC=$NAME"))
        self.assertIn("使えない文字", self.blocked("agentloop-middle SPEC=Cart-2"))

    def test_lake_build_behind_a_variable_directory_is_refused_when_it_may_be_a_proof(self):
        self.assertIn("変数を含む cd", self.blocked("cd $X/tasks/fv/Sort && lake build"))
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "tasks", "fv"))
            self.assertIn("変数を含む cd", self.blocked("cd $X && lake build", cwd=d))


class ScriptTest(unittest.TestCase):
    def run_main(self, text):
        old_in, old_out = sys.stdin, sys.stdout
        sys.stdin, sys.stdout = io.StringIO(text), io.StringIO()
        try:
            code = cmdparse.main()
            return code, sys.stdout.getvalue()
        finally:
            sys.stdin, sys.stdout = old_in, old_out

    def test_as_a_script_it_prints_one_line_per_entry(self):
        payload = json.dumps({"tool_input": {"command": "agentloop-middle SPEC=Cart"}, "cwd": "/r"})
        self.assertEqual(self.run_main(payload), (0, "OK\t/r\tCart\tagentloop-middle\n"))
        self.assertEqual(self.run_main("not json"), (0, ""))
        code = "no_such_code"  # passed as a variable: the message-table check reads literal codes only
        self.assertEqual(cmdparse.msg(code), "未知のメッセージコード: no_such_code")


if __name__ == "__main__":
    unittest.main()
