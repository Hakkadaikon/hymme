"""Signed record store shared by every worktree of a repository.

Records live in <git common dir>/hymme/log.jsonl, so a second worktree or a subagent reads the same
log. Only a hook can sign: the key sits in CLAUDE_PLUGIN_DATA, which a Bash tool command does not get.
shortcut: the key is a file in the user's home, so a worker who reads it on purpose can forge a record.
Upgrade to an out-of-process notary if that has to be ruled out.
"""

import hashlib
import hmac
import json
import os
import secrets
import subprocess
import time
from pathlib import Path

SCHEMA = 1
VERSION = "0.16.0"
KEY_ENV = "CLAUDE_PLUGIN_DATA"
KEY_NAME = "notary.key"


class NoRepo(Exception):
    """Raised when the working directory is not inside a git repository."""


def git(*args, cwd=None):
    out = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, check=False)
    if out.returncode != 0:
        raise NoRepo(out.stderr.strip() or "git failed")
    return out.stdout.strip()


def root(cwd=None):
    """<git common dir>/hymme, the same directory from every worktree."""
    common = Path(git("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=cwd))
    return common / "hymme"


def toplevel(cwd=None):
    return Path(git("rev-parse", "--show-toplevel", cwd=cwd))


def key_path():
    base = os.environ.get(KEY_ENV)
    return Path(base) / KEY_NAME if base else None


def load_key(create=False):
    """The signing key, or None when this process is not a hook (no CLAUDE_PLUGIN_DATA)."""
    path = key_path()
    if path is None:
        return None
    if not path.exists():
        if not create:
            return None
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(secrets.token_hex(32))
        path.chmod(0o600)
    return path.read_text().strip().encode()


def sha256_file(path):
    try:
        return hashlib.sha256(Path(path).read_bytes()).hexdigest()
    except OSError:
        return None


def branch(cwd=None):
    try:
        return git("rev-parse", "--abbrev-ref", "HEAD", cwd=cwd)
    except NoRepo:
        return None


def default_branch(cwd=None):
    """The name of the branch changes are merged into: origin's default, else main, else master."""
    try:
        return git("symbolic-ref", "--short", "refs/remotes/origin/HEAD", cwd=cwd).split("/", 1)[1]
    except (NoRepo, IndexError):
        pass
    for name in ("main", "master"):
        try:
            git("rev-parse", "--verify", "--quiet", f"refs/heads/{name}", cwd=cwd)
            return name
        except NoRepo:
            continue
    return None


def default_base(cwd=None):
    """The commit a change is measured against: the default branch as the remote has it, else the local one.
    A clone made with `remote add` + `push -u` has no origin/HEAD, so the remote branch is tried by name too."""
    name = default_branch(cwd)
    remote = [f"refs/remotes/origin/{name}"] if name else []
    for ref in ("refs/remotes/origin/HEAD", *remote, "refs/heads/main", "refs/heads/master"):
        try:
            return git("rev-parse", "--verify", "--quiet", ref, cwd=cwd)
        except NoRepo:
            continue
    return None


def merge_base(cwd=None, ref="HEAD"):
    base = default_base(cwd)
    if base is None:
        return None
    try:
        return git("merge-base", base, ref, cwd=cwd)
    except NoRepo:
        return None


def change_id(cwd=None, ref="HEAD"):
    """patch-id of the branch's committed change, so a rebase onto a new base keeps the same id."""
    base = merge_base(cwd, ref)
    if base is None:
        return None
    diff = subprocess.run(["git", "diff", base, ref], cwd=cwd, capture_output=True, check=False).stdout
    if not diff.strip():
        return "empty"
    out = subprocess.run(["git", "patch-id", "--stable"], input=diff, cwd=cwd, capture_output=True, check=False)
    return out.stdout.decode().split()[0] if out.stdout.strip() else None


def changed_files(cwd=None, ref="HEAD"):
    """Paths the branch changed, committed or not, relative to the repository root."""
    base = merge_base(cwd, ref)
    names = set()
    untracked = ["ls-files", "--others", "--exclude-standard"]
    for args in (["diff", "--name-only", base, ref] if base else None, ["diff", "--name-only", "HEAD"], untracked):
        if args:
            try:
                names.update(n for n in git(*args, cwd=cwd).splitlines() if n)
            except NoRepo:
                pass
    return names


def _canonical(record):
    body = {k: v for k, v in record.items() if k != "sig"}
    return json.dumps(body, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()


def sign(record, key):
    return hmac.new(key, _canonical(record), hashlib.sha256).hexdigest()


def append(kind, fields, cwd=None, key=None):
    """Append one record. With a key (hook process) the record is signed; without one it is a note."""
    base = root(cwd)
    base.mkdir(parents=True, exist_ok=True)
    record = {"schema": SCHEMA, "version": VERSION, "kind": kind, "ts": time.time(), **fields}
    if key:
        record["sig"] = sign(record, key)
    with open(base / "log.jsonl", "a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")
    return record


def records(cwd=None, key=None, kind=None, **match):
    """Records in log order. With a key only the ones whose signature verifies are returned."""
    try:
        lines = (root(cwd) / "log.jsonl").read_text(encoding="utf-8").splitlines()
    except (OSError, NoRepo):
        return []
    out = []
    for line in lines:
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if not isinstance(rec, dict) or (kind and rec.get("kind") != kind):
            continue
        if any(rec.get(k) != v for k, v in match.items()):
            continue
        if key and not hmac.compare_digest(str(rec.get("sig", "")), sign(rec, key)):
            continue
        out.append(rec)
    return out
