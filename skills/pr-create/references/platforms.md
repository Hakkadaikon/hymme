# プラットフォーム別リファレンス

PR/MR 作成の CLI コマンド・テンプレート配置・フォールバックをプラットフォームごとにまとめる。プラットフォーム・ベースブランチ・push 状態の判定は `scripts/pr-context.sh`（SKILL.md §1）が出力するので、ここでは扱わない。スクリプトの `PLATFORM` セクションが指す CLI の該当節を読む。

## 共通の前提

- **push は無断で行わない**。未 push のブランチは、作成直前に AskUserQuestion で push 可否の承認を取ってから push する（SKILL.md §7）。承認が得られなければ push せず停止。SSH 認証（publickey）で弾かれる非対話環境では、push コマンドを提示してユーザーに実行を委ねる。
- **作成は draft 既定**、**作成前にユーザー承認**。
- 本文は一時ファイルに書いてファイル渡しで渡す（改行・特殊文字の崩れを避ける。hook が本文の「影響の範囲」と「検証」の見出しを読めるのも、`--body` などの引数か実在するファイルで渡したときだけ）。一時ファイルはセッションの scratchpad 等リポジトリ外の一時領域に置き、作成後は不要なら削除。
- **どの入口にも同じ検査が掛かる**。`gh pr create`、`glab mr create`、`gh api …/pulls` への POST、PR / MR を作る MCP の道具、既定ブランチでの `git merge`、PR 作成後の `git push` は、どれも統合の入口として hook が検査する（確かめられることは SKILL.md §1.5）。CLI を替えても検査は外れない。

## GitHub (`gh`)

CLI が `installed: no` のときは認証も含め `gh auth status` で確認し、不可なら手動作成へ。

### テンプレート配置（探索順）
1. `.github/pull_request_template.md`
2. `.github/PULL_REQUEST_TEMPLATE.md`
3. `pull_request_template.md`（ルート）
4. `docs/pull_request_template.md`
5. `.github/PULL_REQUEST_TEMPLATE/*.md`（複数テンプレ。`?template=` 相当。候補提示）

### 作成
```bash
gh pr create \
  --base "<base>" \
  --head "<current-branch>" \
  --title "<title>" \
  --draft \
  --body-file "<本文を書いた一時ファイル>"
```
- 非 draft 指定時は `--draft` を外す。
- `--body "..."` は短文のみ。標準入力（`--body-file -`）やプロセス置換で渡すと、hook は本文を読めず、見出しの検査が掛からない。ファイルで渡す。
- ブラウザで開くだけにしたいなら `--web`（テンプレ自動適用されるが、こちらで埋めた本文は渡らない点に注意）。

### 既存 PR 確認
```bash
gh pr list --head "<current-branch>"   # 既に PR があれば二重作成を避ける
```

## GitLab (`glab`)

### テンプレート配置
- `.gitlab/merge_request_templates/*.md`（`Default.md` があれば既定）

### 作成
```bash
glab mr create \
  --target-branch "<base>" \
  --source-branch "<current-branch>" \
  --title "<title>" \
  --draft \
  --description "<body>"
```
- GitLab の draft はタイトル先頭 `Draft:` でも表現される。`--draft` フラグが効かない版では `Draft: <title>` を使う。
- description は引用符の中に本文をそのまま書いて渡す。`--description "$(cat <file>)"` の形は使わない。hook はコマンド置換の中身を読めず、「影響の範囲」と「検証」の見出しが無いと判定して止める。

## その他・フォールバック

GitHub/GitLab 以外（Gitea, Bitbucket, codeberg 等）、または対応 CLI が見つからない・未認証の場合:

1. push 状態を確認（未 push なら §7 の承認フローで push 可否を確認。承認されれば push）。
2. 生成したタイトルと本文をチャットに提示。
3. 該当プラットフォームの Web UI で作成するよう案内し、本文をそのまま貼り付けられる形で渡す。Web UI での作成は hook から見えないので、渡す前に SKILL.md §1.5 の表（統合の入口で確かめられること）を自分で確かめ、結果を本文の「検証」に書く。
4. 該当 CLI（例: `tea`）が使えそうなら、ユーザーに利用可否を確認してからコマンドを提案する。
