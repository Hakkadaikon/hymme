# 段の宣言

hymme 自身の開発で使う段です。コマンドは先頭一致で照合されます。

- unit コマンド: `python3 -m unittest discover -s loopeng/lib/tests`
- unit パス: loopeng/lib/tests/*
- integration コマンド: `nix flake check`
- integration パス: scripts/*.test.sh
- e2e コマンド: `bash scripts/real-session.sh`
- e2e パス: scripts/real-session.sh
- ci コマンド: `gh run watch --exit-status`
