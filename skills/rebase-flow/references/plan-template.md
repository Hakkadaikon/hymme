# rebase 計画テンプレート(§3 承認ゲートで提示する)

内容はスクリプト出力からの転記を基本とし、創作しない。

````markdown
## rebase 計画: <目的を一言>

### 現在の状態
- ブランチ: `<branch>`（HEAD: `<sha7>`、backup 予定名: `backup/rebase/<branch>-<ts>`）
- push 状態: <未 push / push 済み N 件が書き換え対象 → 完了後に force-push が必要>
- WARNING: <スクリプトの WARNING 全件。無ければ「なし」>

### rebase が必要な理由
<ユーザーの依頼・目的。理由を書けない rebase は実行しない>

### これから何をするか
実行コマンド（この通りに実行する）:
```
bash <skill-dir>/scripts/rebase-backup.sh
GIT_SEQUENCE_EDITOR="cp <todo-path>" git rebase -i <base-ref>
```
todo 全文（interactive の場合）:
```
pick abc1234 ...
```
対象コミット（REWRITE RANGE より）:
```
<git log --oneline>
```
親子関係（GRAPH より）:
```
<graph>
```

### 期待される rebase 後の状態
<コミット列がどうなるか: 件数・メッセージ・base との関係を具体的に>

### コンフリクト予測
<なし / ファイル一覧と解消方針>

### 失敗時の影響と復旧
- 影響範囲: <このブランチのみ / open PR #N のレビュー文脈 / 子ブランチ X の孤立 等>
- rebase 中断: `git rebase --abort`（いつでも可・開始前に完全復帰）
- 完了後の巻き戻し: backup へ reset（reset-flow スキル経由）
````
