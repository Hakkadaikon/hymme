#!/usr/bin/env python3
"""Middle-loop meta-oracle: does the TLA+ spec actually catch bugs?

Mutation testing for design specs. We inject small mutations into a .tla file
(flip a comparison, drop a conjunct, weaken a guard) and run TLC. A spec that is
worth anything must FAIL (find a counterexample / invariant violation) on the
mutant. A mutant that still passes is a "survivor": the spec is too weak to
distinguish correct behaviour from that bug -- the oracle reports it.

Only a property violation (or a timeout) counts as "killed". A mutant that TLC
rejects as unparsable is "invalid" (it tested nothing), and one that stops on a
TLC runtime error ("Successor state is not completely specified", exceptions)
is "unverified": re-check it with a semantic variant before trusting it
(skills/loopeng-modelcheck/references/mutation-oracle.md).

Exit: 0 = no survivors and nothing unverified (or, with --since, no mutation
site on the changed lines), 1 = survivors, 2 = the baseline spec doesn't pass,
3 = no survivors but nothing to trust yet (some mutants are unverified, or no
valid mutant was killed), 4 = --since could not read the change (not a git
repository, or an unknown revision).

Usage:
    tla_mutate_oracle.py <spec.tla> [--cfg spec.cfg] [--workers N]
                         [--jobs N] [--since REV]

--jobs N runs N mutants at once (default: the CPUs this process may use);
each TLC run then uses one worker, so --workers only applies with --jobs 1.
Running mutants at once slows each of them: on a heavy spec, lower --jobs or
raise --mut-timeout when mutants time out (a timeout counts as killed).

--since REV mutates only the spec lines changed since the git revision REV
(a spec git does not track yet counts as all new). That is enough for a local
edit; run the full set when a change touches definitions that many actions or
properties read.
"""

import argparse
import concurrent.futures
import os
import re
import shutil
import subprocess
import sys
import tempfile

# 要約行の mutants:/killed:/... と変異ごとの判定語(killed/SURVIVOR/invalid/UNVERIFIED)は
# テストと skills/loopeng-modelcheck/references/mutation-oracle.md が目印として読むので訳さない。
MESSAGES = {
    "description": (
        "TLA+ spec の mutation oracle。spec に小さな変異を入れて TLC を回し、"
        "spec が変異を検出(killed)できるかを調べる。"
        "終了コード: 0 = survivor も unverified も無い(--since で変えた行に変異箇所が無いときも 0)、"
        "1 = survivor あり、2 = 変異前の spec が通らない、"
        "3 = survivor は無いが unverified が残るか killed が 0 件、4 = --since の変更を読めない"
    ),
    "help_spec": ".tla spec のパス",
    "help_cfg": "TLC の設定ファイル(省略時は <spec>.cfg があれば使う)",
    "help_workers": "1 回の TLC のワーカー数(既定は auto。--jobs 1 のときだけ効く)",
    "help_mut_timeout": "変異 1 つあたりの TLC のタイムアウト秒(既定 60)",
    "help_jobs": "同時に回す変異の数(既定: このプロセスが使える CPU の数)",
    "help_since": "この git リビジョンから変えた行だけに変異を入れる",
    "no_tlc": "エラー: PATH に `tlc` が無く、java + TLA_JAR の代替も無い",
    "timeout": "TLC が {timeout} 秒でタイムアウトした(killed として扱う)",
    "since_bad_rev": "--since {rev}: git リポジトリの外か、そのリビジョンが無い",
    "since_diff_failed": "--since {rev}: git diff に失敗した: {err}",
    "no_spec": "エラー: spec が無い: {spec}",
    "error": "エラー: {err}",
    "workers_ignored": "注意: --jobs {jobs} では --workers {workers} を無視する(各 TLC は 1 ワーカー)",
    "baseline_fails": "変異前の spec が通らない。mutation testing の前に spec を直す:\n",
    "since_mutating": "{rev} から変えた {lines} 行にある {sites} か所に変異を入れる",
    "mutant": "  {kind:<9} {label}",
    "timeouts": (
        "警告: --jobs {jobs} で {n} 個の変異がタイムアウトした。タイムアウトは killed に数える。"
        "--jobs を下げるか --mut-timeout を延ばして回し直してから、その killed を信じる。"
    ),
    "summary": (
        "\nmutants: {total}  killed: {killed}  survivors: {survivors}  unverified: {unverified}  invalid: {invalid}"
    ),
    "unverified": "性質ではなく TLC のエラーで止まった。意味の通る書き換えで再検査する: {labels}",
    "too_weak": "spec が弱く、次の変異を検出できない: {labels}",
    "unverified_only": "survivor は無いが、上の unverified の変異はまだ証拠にならない。",
    "no_sites": "{rev} から変えた行に変異を入れる箇所が無い。",
    "nothing_killed": "有効な変異が 1 つも killed にならなかった。何も検査していない。",
    "tight": "spec は有効な変異をすべて検出した。設計の不変条件は十分に締まっている。",
}


def msg(code, **kw):
    """端末に出す文言をコードから引く(文言をこの表1か所に集める)。"""
    return MESSAGES[code].format(**kw)


# (name, pattern, replacement) -- each flips one operator to inject a bug.
MUTATIONS = [
    ("lt->le", re.compile(r"(?<![<>=/\\])<(?![<>=])"), "\\\\leq"),
    ("le->lt", re.compile(r"\\leq"), "<"),
    ("gt->ge", re.compile(r"(?<![<>=/\\])>(?![<>=])"), "\\\\geq"),
    ("eq->neq", re.compile(r"(?<![<>=/\\:])=(?![<>=])"), "#"),
    ("and->or", re.compile(r"/\\"), "\\\\/"),
    ("plus->minus", re.compile(r"(?<![+])\+(?![+])"), "-"),
]


PARSE_FAIL = re.compile(
    r"Parsing or semantic analysis failed|\*\*\* ?Parse Error ?\*\*\*|Semantic errors|Fatal errors while parsing"
)
VIOLATION = re.compile(r"\b(is|was|were) violated\b")


def run_tlc(spec_path, cfg, workers, timeout=600):
    """Return (kind, output): kind is one of
    "pass" (no error), "violation" (an invariant/property is violated),
    "invalid" (parse/semantic error), "error" (other TLC error), "timeout".

    A TLC run that exceeds `timeout` counts as killed: a mutant
    that diverges the state space no longer behaves like the correct spec, so
    the design distinguishes it. This also stops one runaway mutant (e.g. a
    sign flip that loops forever in Nat) from hanging the whole oracle.
    """
    jar = os.environ.get("TLA_JAR")
    # Prefer the flake `tlc` wrapper (bundles its own JDK). Only fall back to
    # `java -cp $TLA_JAR` when no wrapper exists AND java is actually present.
    if shutil.which("tlc"):
        cmd = ["tlc"]
    elif jar and shutil.which("java"):
        cmd = ["java", "-cp", jar, "tlc2.TLC"]
    else:
        sys.exit(msg("no_tlc"))
    # Each run gets its own scratch directory: TLC's default (states/ next to
    # the spec) would be shared by mutants running at the same time.
    metadir = tempfile.mkdtemp(prefix="tlc-states-")
    # -noGenerateSpecTE: no <Spec>_TTrace_* files next to the spec on violations.
    cmd += ["-workers", str(workers), "-deadlock", "-metadir", metadir, "-noGenerateSpecTE"]
    if cfg:
        cmd += ["-config", cfg]
    cmd.append(os.path.basename(spec_path))
    try:
        proc = subprocess.run(
            cmd,
            cwd=os.path.dirname(spec_path) or ".",
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return "timeout", msg("timeout", timeout=timeout)
    finally:
        shutil.rmtree(metadir, ignore_errors=True)
    out = proc.stdout + proc.stderr
    if PARSE_FAIL.search(out):
        return "invalid", out
    if VIOLATION.search(out):
        return "violation", out
    # TLC exits non-zero on any error; "No error" appears on a clean run.
    if proc.returncode == 0 and "Error:" not in out:
        return "pass", out
    return "error", out


def apply_one_mutation(src, name, pat, repl):
    """Return list of (label, mutated_src) -- one per matched site."""
    out = []
    for i, m in enumerate(pat.finditer(src)):
        mutated = src[: m.start()] + re.sub(pat, repl, m.group(), count=1) + src[m.end() :]
        if mutated != src:
            out.append((f"{name}#{i}@{m.start()}", mutated))
    return out


def usable_cpus():
    """CPUs this process may run on (cgroup/affinity aware where possible)."""
    if hasattr(os, "sched_getaffinity"):
        return len(os.sched_getaffinity(0))
    return os.cpu_count() or 1


class SinceError(Exception):
    """--since cannot read the change."""


def git(spec, *args):
    return subprocess.run(["git", *args], cwd=os.path.dirname(spec), capture_output=True, text=True)


def changed_lines(spec, rev):
    """1-based line numbers of `spec` added or changed since git revision `rev`.
    A spec git does not track yet is new: every line counts as changed."""
    if git(spec, "rev-parse", "--verify", "--quiet", rev + "^{commit}").returncode != 0:
        raise SinceError(msg("since_bad_rev", rev=rev))
    name = os.path.basename(spec)
    if git(spec, "ls-files", "--error-unmatch", "--", name).returncode != 0:
        return set(range(1, len(open(spec).read().splitlines()) + 1))
    diff = git(spec, "diff", "--no-color", "--no-ext-diff", "-U0", rev, "--", name)
    if diff.returncode != 0:
        raise SinceError(msg("since_diff_failed", rev=rev, err=diff.stderr.strip()))
    out = diff.stdout
    lines = set()
    for m in re.finditer(r"^@@ -\S+ \+(\d+)(?:,(\d+))? @@", out, re.M):
        start, count = int(m.group(1)), int(m.group(2) or 1)
        lines.update(range(start, start + count))
    return lines


def line_of(src, label):
    """Line of the mutation site; labels end in @<offset into src>."""
    return src.count("\n", 0, int(label.rsplit("@", 1)[1])) + 1


def run_mutant(spec, mutated, cfg, workers, timeout):
    """TLC on one mutant, written next to the spec (so EXTENDS resolve)
    under a module name equal to its file name, as SANY requires."""
    with tempfile.NamedTemporaryFile(
        "w",
        suffix=".tla",
        dir=os.path.dirname(spec),
        delete=False,
        prefix=os.path.basename(spec)[:-4] + "_mut_",
    ) as tf:
        mod = os.path.basename(tf.name)[:-4]
        tf.write(re.sub(r"^----+ MODULE \w+", f"---- MODULE {mod}", mutated, count=1))
        path = tf.name
    try:
        return run_tlc(path, cfg, workers, timeout)[0]
    finally:
        os.unlink(path)


def main():
    ap = argparse.ArgumentParser(description=msg("description"))
    ap.add_argument("spec", help=msg("help_spec"))
    ap.add_argument("--cfg", help=msg("help_cfg"))
    ap.add_argument("--workers", default=None, help=msg("help_workers"))
    ap.add_argument("--mut-timeout", type=int, default=60, help=msg("help_mut_timeout"))
    ap.add_argument("--jobs", type=int, default=usable_cpus(), help=msg("help_jobs"))
    ap.add_argument("--since", metavar="REV", help=msg("help_since"))
    args = ap.parse_args()

    spec = os.path.abspath(args.spec)
    if not os.path.isfile(spec):
        sys.exit(msg("no_spec", spec=spec))
    cfg = args.cfg or (spec[:-4] + ".cfg" if spec.endswith(".tla") else None)
    if cfg and not os.path.isfile(cfg):
        cfg = None

    src = open(spec).read()
    # Read the change before the (slow) baseline run, so a bad --since fails fast.
    changed = None
    if args.since:
        try:
            changed = changed_lines(spec, args.since)
        except SinceError as e:
            print(msg("error", err=e))
            return 4
    if args.workers is not None and args.jobs > 1:
        print(msg("workers_ignored", workers=args.workers, jobs=args.jobs))

    # Sanity: the unmutated spec must pass, else mutation results are meaningless.
    base_kind, base_out = run_tlc(spec, cfg, args.workers or "auto")
    if base_kind != "pass":
        print(msg("baseline_fails"))
        print(base_out[-2000:])
        return 2

    mutants = [m for name, pat, repl in MUTATIONS for m in apply_one_mutation(src, name, pat, repl)]
    if changed is not None:
        mutants = [m for m in mutants if line_of(src, m[0]) in changed]
        print(msg("since_mutating", sites=len(mutants), lines=len(changed), rev=args.since))

    # With several mutants at once, give each TLC one worker.
    workers = 1 if args.jobs > 1 else (args.workers or "auto")
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(args.jobs, 1)) as pool:
        kinds = list(pool.map(lambda m: run_mutant(spec, m[1], cfg, workers, args.mut_timeout), mutants))

    survivors, unverified, killed, invalid, total = [], [], 0, 0, len(mutants)
    for (label, _), kind in zip(mutants, kinds, strict=True):
        if kind == "pass":
            survivors.append(label)  # spec did NOT catch the bug
            print(msg("mutant", kind="SURVIVOR", label=label))
        elif kind == "invalid":
            invalid += 1  # mutant doesn't parse: it tested nothing
            print(msg("mutant", kind="invalid", label=label))
        elif kind == "error":
            unverified.append(label)  # stopped on a TLC error, not on a property
            print(msg("mutant", kind="UNVERIFIED", label=label))
        else:
            killed += 1
            print(msg("mutant", kind="killed", label=label))

    timeouts = sum(1 for k in kinds if k == "timeout")
    if timeouts and args.jobs > 1:
        print(msg("timeouts", n=timeouts, jobs=args.jobs))
    print(
        msg(
            "summary",
            total=total,
            killed=killed,
            survivors=len(survivors),
            unverified=len(unverified),
            invalid=invalid,
        )
    )
    if unverified:
        print(msg("unverified", labels=", ".join(unverified)))
    if survivors:
        print(msg("too_weak", labels=", ".join(survivors)))
        return 1
    if unverified:
        print(msg("unverified_only"))
        return 3
    if total == 0 and args.since:
        print(msg("no_sites", rev=args.since))
        return 0
    if killed == 0:
        print(msg("nothing_killed"))
        return 3
    print(msg("tight"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
