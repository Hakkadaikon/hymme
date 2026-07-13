---
name: rebase-flow
description: "git rebase / git pull --rebase を伴う操作の安全運用ルール。履歴書き換えは復旧不能な事故になり得るため、rebase 系コマンドを 1 つでも実行する前に必ず本スキルを参照する。「rebase して」「main に追従して」「ブランチを最新化して」「コミットをまとめて / 整理して」「squash して」「fixup を畳んで」「履歴をきれいにして」「force-push して」と依頼される、PR 前に履歴を整える、コンフリクト解消のために rebase する、といった場面すべてが対象。決定論スクリプトによるガードレール判定（保護ブランチ・push 済み範囲・子ブランチ・進行中操作・コンフリクト予測）→ 計画提示 → ユーザー承認 → backup ブランチ作成 → 非対話実行 → range-diff / tree 同一性による機械検証、のゲートを固定化する。同梱の git-guard hook により backup 作成（解錠）なしの git rebase は機械的にブロックされる。"
user-invocable: true
argument-hint: "[base-ref と目的（例: origin/main に追従 / HEAD~4 を squash）]"
---

# rebase 安全運用

rebase は日常操作の中で唯一、確定済みの履歴を破壊できる。事故は「状態を確かめずに始める」「復旧手段を用意せずに始める」ことで起きる。本スキルは **収集 → 計画提示 → 承認 → backup + 実行 → 機械検証** の 5 段ゲートを固定手順にする。どの段も飛ばさない。

環境側の強制: 本プラグイン同梱の PreToolUse hook（`hooks/git-guard.sh`）が `git rebase` を監視しており、`scripts/rebase-backup.sh` が置く解錠 marker（30 分有効）が無い実行は機械的に deny される。つまり **このワークフローを通らない rebase はそもそも実行できない**。`git rebase --abort` のみ常時許可（脱出経路）。

## 制約（厳守）

1. **承認なし実行禁止** — §3 の計画を提示し、ユーザーの明示承認を得るまで rebase 系コマンドを実行しない。`git pull --rebase` も rebase である。
2. **backup なし実行禁止** — 承認後に `scripts/rebase-backup.sh` で backup ブランチを作成してから実行する（guard の解錠もこれが行う）。
3. **BLOCKER で停止** — context スクリプトが `BLOCKER:` を出したら計画に進まない（保護ブランチ・dirty tree・進行中操作・対象 0 件など）。解消方法はユーザーと相談する。
4. **WARNING は承認対象** — `WARNING:` は全て計画に転記する。ユーザーが読まずに承認できる形に隠さない。
5. **force-push の制限** — 生の `git push --force`/`-f` は git-guard hook が拒否する。force push は検証済み tip を明示した **`--force-with-lease=<branch>:<sha>` のみ**。§7 の手順で検証完了後、push 単独の承認を得てから。対象は作業ブランチのみで、保護ブランチ（main/master/trunk/release/リモート既定ブランチ等）への force は不可。
6. **予測外コンフリクトは即 abort** — 計画のコンフリクト予測に無い衝突が出たら `git rebase --abort` して報告。粘らない。
7. **エディタを開かない** — todo は `GIT_SEQUENCE_EDITOR` で流し込み、メッセージ変更は `exec git commit --amend -m`（references/todo-patterns.md）。エディタ起動はセッションをハングさせる。
8. **backup の削除はユーザー承認制** — 検証が通っても勝手に消さない。reflog・gc には触れない。
9. **承認済みコマンドを一字一句そのまま実行** — 実行時にフラグを足さない・変えない。変更が必要になったら計画からやり直す。
10. **巻き戻しは reset-flow スキル経由** — rebase 完了後に取り消す場合の `git reset --hard <backup>` は本スキルでは実行せず、reset-flow スキルのワークフローに委ねる。

## rebase の 2 類型

| 型 | 用途 | base-ref の例 | 合格基準（§5） |
|---|---|---|---|
| **onto**（追従） | base の先端へ乗せ替え | `origin/main` | range-diff で全コミット対応・意図しない drop なし |
| **history-edit**（整理） | squash / reword / drop / reorder | `HEAD~5` | **tree 同一性 = 必須**（drop 計画時を除く）+ range-diff |

追従と整理を両方やる場合は**必ず 2 回に分け、それぞれ承認を取る**（先に整理 → tree 同一性で検証 → 次に追従）。整理を先にすると追従時に replay するコミットが減りコンフリクトも減る。1 回に混ぜると検証基準が曖昧になる。

そもそも rebase が必要かも最初に問う。ユーザーが rebase を明示していないなら、履歴を書き換えない代替（merge での追従など）を先に提示してよい。書き換えない選択が最強のガードレール。

## ワークフロー

### 1. コンテキスト収集

```bash
bash <skill-dir>/scripts/rebase-context.sh <base-ref>
```

base-ref: onto 型 → rebase 先（fetch 済みの `origin/main` を優先）。history-edit 型 → 書き換え範囲の直前コミット（`HEAD~N` / SHA）。

読むべきセクション:

- **SUMMARY / BLOCKER / WARNING** — 制約 3・4 の判定材料。
- **BASE REF の type** — onto / history-edit 判定。想定と違えば base-ref を見直す。
- **PUSH STATUS** — `push 済みコミット N 件` が出たら §7 の force-push 手順が後続することを計画に書く。
- **CHILD BRANCHES** — 子ブランチが切り離される影響と扱い（各自 `rebase --onto` するか放置か）を計画に書く。
- **CONFLICT PREDICTION** — 予測衝突ファイル。§4 の解消方針の素材。
- **REWRITE RANGE / GRAPH** — 計画テンプレへ転記する素材。

### 2. 操作の決定

型を確定し、interactive（history-edit）なら todo をファイルに書く（scratchpad 推奨）。todo の組み方・非対話レシピは **references/todo-patterns.md を必ず読む**。todo は全文が承認対象。

### 3. 計画提示（承認ゲート）

`references/plan-template.md` のテンプレで提示する。内容はスクリプト出力からの転記を基本とし、創作しない。
提示後、ユーザーの明示承認を待つ。修正要望が出たら計画を作り直して再提示する。

### 4. 実行

1. `bash <skill-dir>/scripts/rebase-backup.sh` — BACKUP / RECOVERY 出力を保持。これが guard を解錠する（30 分）。
2. 承認済みコマンドを一字一句そのまま実行する。
3. コンフリクトで停止したら:
   - **予測済み** → 解消案（該当ファイルの diff）を提示 → 承認 → `git add <files>` → `GIT_EDITOR=true git rebase --continue`
   - **予測外** → 即 `git rebase --abort` → 状況報告（制約 6）
4. 完走を確認する（`git status` に rebase 進行表示が無いこと）。

### 5. 検証

```bash
bash <skill-dir>/scripts/rebase-verify.sh <backup-branch> <base-ref>
```

base-ref には §1 の BASE REF セクションに表示された **SHA** を渡す。`HEAD~N` の相対指定は rebase 後には別のコミットを指すため使わない。

- **history-edit**: `TREE IDENTITY: identical: yes` が合格条件（drop を含む計画では drop 分の差だけが出ることを確認）。
- **onto**: range-diff で before/after の全コミットが対応していること。計画に無い `<`（消失）は異常。
- 異常時は勝手に修復しない。検証結果を報告し、巻き戻すなら reset-flow スキルへ（references/recovery.md）。

### 6. 報告

以下を報告する: 実行したコマンド / range-diff・tree 同一性の結果 / backup ブランチ名 / リモート反映が必要ならその手順（§7）。

### 7. push（必要な場合のみ）

PUSH STATUS が force-push 必要を示していた場合:

1. `git fetch <remote> <branch>` → `tip=$(git rev-parse <remote>/<branch>)`
2. 安全確認: `git merge-base --is-ancestor $tip <backup>` — **backup の祖先でなければ rebase 中に他者 push があった。停止して報告**。
3. push コマンドを単独で提示し、明示承認を得る（rebase の承認とは別に取る）。
4. 明示 lease で実行:
   ```bash
   git push <remote> <branch> --force-with-lease=<branch>:$tip
   ```
   lease に手順 2 の検証済み tip を明示することで、確認時点から他者 push が挟まったら確実に拒否される。生の `git push --force`/`-f`・値なしの `--force-with-lease` は git-guard hook に弾かれるので使わない。
5. lease 拒否（stale info）= 確認後に他者 push があった。自動リトライせず手順 1 からやり直す。

書き換え対象が全て未 push なら通常 push（これも承認後）。

## 参照

- `scripts/rebase-context.sh` — ガードレール判定（BLOCKER/WARNING）+ 計画素材の read-only 収集（§1）
- `scripts/rebase-backup.sh` — backup ブランチ作成 + guard 解錠 + 復旧コマンド提示（§4）
- `scripts/rebase-verify.sh` — tree 同一性 / range-diff による事後検証 + guard 再施錠（§5）
- `references/plan-template.md` — §3 承認ゲートで提示する計画テンプレ
- `references/todo-patterns.md` — interactive rebase の非対話 todo レシピ（reword / squash / drop / 並べ替え / autosquash）。§2 で必読
- `references/recovery.md` — 失敗パターン別の復旧手順。コンフリクトで停止した・結果が想定と違う・force-push 後に戻したい時に読む
- 関連スキル: commit-flow（整理後のメッセージ規約）/ reset-flow（巻き戻し実行）
