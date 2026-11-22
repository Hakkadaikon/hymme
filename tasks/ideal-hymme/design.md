# 新しい強制の仕組み(実装済みの中核の説明)

スキルの文面を書き直す人のための説明です。実装は `agentloop/lib/hymme/` にあり、テストは `agentloop/lib/tests/test_hymme.py` です。ここに書いた動作は、すべてテストで確かめてあります。

## 考え方

- 検査が読むのは、hook が書いた署名つきの記録だけです。作業する本人が台帳に付けたチェックは、合格の根拠になりません。
- 記録は `<git の共通ディレクトリ>/hymme/log.jsonl` に置きます。別の worktree やサブエージェントからも同じ記録が見えます。
- 署名の鍵は `CLAUDE_PLUGIN_DATA` にあり、hook だけが使えます。鍵と記録の置き場を名指しするコマンドや道具の呼び出しは止まります。
- 作業者の承認は、作業者の入力の全文が `承認 <8桁の符号>` の1行に一致したときだけ記録されます。符号は申請の内容のハッシュから決まります。
- hook の入口は `hooks/hymme_hook.py` の1つです。PreToolUse(すべての道具)、PostToolUse と PostToolUseFailure(Bash)、SubagentStop、UserPromptSubmit から呼ばれます。
- 既存の `verifiability-gate.sh`(指標)、`agentloop-lint-gate.sh`、`git-guard.sh`、`test-design-extract-gate.sh` は残っています。`pr-review-gate` と `agentloop-extract-gate.sh` は新しい入口に置き換えました。

## 検証の入口

次のコマンドを「検証の入口」と呼びます。`cd` の連結、`env`、`timeout`、`nix develop -c`、`bash -c` の中も見つけます。

- `agentloop-outer` / `agentloop-middle` / `agentloop-inner`(`make -f … agentloop-*` も)
- `smt_oracle.py <…>.smt.py`
- `trace_check.py <…>.tla <ログ>.jsonl`
- `tasks/fv/<名前>` での `lake build`
- `tlc`、`java … tlc2.TLC`、`apalache-mc` の直接の実行

入口の前に、名前ごとに次を確かめます。満たさなければ止まります。

1. 抽出の台帳 `tasks/loopeng/<名前>.extract.md` が閉じている。「## 台帳」に未チェックと欠番が無く、「## 閉じる前のチェック」にも未チェックと空の行が無い。`lake build` だけはこの検査をしない(`tasks/fv` は性質カタログを持ち、formal-verification の reviewer が見る)。
2. 確認の一覧 `tasks/loopeng/<名前>.claims.md`(Lean は `tasks/fv/<名前>.claims.md`)があり、形が整っていて、今の内容を作業者が承認している。
3. 検証容易性の台帳に対象のコードがあるなら、reviewer の合格の記録がある。記録は台帳と対象のファイルのハッシュに結び付いていて、どちらかを変えると失効する。
4. 同じ名前が、修正を挟んで同じ規則で2回続けて落ちているなら、`tasks/loopeng/<名前>.premise.md` に「- 前提:」「- 観測:」「- 結果:」が書かれている(2回目の失敗より新しいこと)。「修正を挟んで」は、2回の実行のあいだに `<名前>.tla`、`.cfg`、`.smt.py` のどれかが変わっていることで判定する。
5. `trace_check.py` だけは、状態の図も要る。`tasks/loopeng/<名前>.chart.md` が今の spec から作られ、破れた規則と検査されなかった規則が無く、作業者が承認している。

検証の入口の検査は、コマンドを実行したディレクトリの `tasks/` を見ます(実行した場所か引数のパスが `tasks/loopeng/`・`tasks/fv/` の中なら、その `tasks/` の手前)。`hymme` コマンドと統合の入口の検査は、リポジトリ直下の `tasks/` を見ます。台帳はリポジトリ直下に置き、入口はリポジトリ直下から実行します。

### 確認の一覧の形

```markdown
# <名前> で確かめること

## 実証する項目

| 要件 | 示すこと | 示さないこと | 破れたときの害 |
|---|---|---|---|
| <要件を平文で1文> | <検証が示すこと> | <検証が示さないこと> | <破れると誰がどう困るか> |

## 有限にした範囲

- <上限や値の範囲。無ければ「無し: 理由」>

## 扱わない領域

- <モデルから捨てた領域と、それを別にどう確かめるか。無ければ「無し: 理由」>
```

手法の用語と管理番号(TLA+、TLC、EARS、SMT、Z3、Lean、Inv、S-001、不変条件、モデル検査、mutation など)が入っていると、形の検査で落ちます。作業者が検証の言語を知らなくても判断できる文にします。表のセルと下の2節の行に `<` があると、ひな形の書きかけとして空の扱いになり、同じく落ちます。

### 承認の流れ

1. 作業する本人が `hymme claims request <名前>` を実行する。形を検査し、申請を作る。
2. hook が、一覧のファイルの中身と符号を作業者に表示する(本人の要約ではなく、ファイルの中身そのもの)。
3. 作業者が `承認 <符号>` とだけ入力する。hook が承認を記録する。
4. 一覧を1文字でも変えると、承認は失効する。

サブエージェントや無人の実行では作業者が入力できません。承認が無ければ、着手せずに BLOCKED で返します。

状態の図も同じ流れです。`hymme chart draw <名前>` で図と結果を作り、`hymme chart request <名前>` で申請します。

## 実行の記録

Bash のコマンドが終わると、hook が終了コードつきで記録を書きます。

- 検証の入口の実行(名前、種類、終了コード、落ちた規則、spec のハッシュ、変更の ID)。`unverified` が出力にあれば「判定できない」と記録し、合格に数えません。`trace_check.py` は、ログの種類(ファイル名の末尾の `.normal.jsonl` など)とログのハッシュも記録します。
- `verifiability.py tasks/verifiability/<名前>.md` の実行。
- 検証容易性の台帳に `突き合わせ: <コマンド>` の行があれば、そのコマンドで始まる実行(実関数とモデルの突き合わせ)。
- `tasks/surface.md` の「確認のコマンド」で始まる実行(実物での確かめ)。
- `tasks/stages.md` で宣言した段のコマンドの実行。
- `hymme capture <ログ> -- <コマンド>` で採ったログのハッシュ。

変更の ID は、ブランチにコミットした差分の patch-id です。rebase しても変わらず、コミットした差分が変わると変わります。コミットしていない変更は ID に入らないので、統合の入口が求める実行は、変更をコミットし終えてから行います。

## reviewer の判定

reviewer が返ったときに、hook が最後のメッセージから判定を読み、記録します。reviewer は最後に次の行を必ず書きます。

- `hymme:verification-reviewer`: `判定: 合格 対象=<系統> 名前=<名前>` か `判定: 不合格 対象=<系統> 名前=<名前>`。系統は verifiability、agent-loop、test-design、formal-verification のどれか。
- `hymme:diff-reviewer`: `must: <件数>`、`lenses: <レンズをカンマ区切り>`、`claim_only: <件数>` の3行。`claim_only` は、確かさの段階が「主張のみ」の must 指摘と「全経路で守られる」という主張の件数。

台帳の「- [x] レビュー合格」の行と `tasks/diff-review/evidence.md` は、もう検査に使いません。

## 統合の入口

次を「統合の入口」と呼びます。変更がブランチの外へ出る経路です。

- `gh pr create`、`glab mr create`、`gh api …/pulls` への POST
- 道具の名前に `create_pull_request` か `create_merge_request` を含む MCP の道具
- 既定のブランチの上での `git merge`
- PR を作ったあとのブランチでの `git push`

統合の入口の前に、次を確かめます。

| 確かめること | 例外で外せるか |
|---|---|
| この変更の ID に対する diff-review の記録があり、レンズの組ごとの最新の記録で must と claim_only が 0 | review |
| 閉じていない欠陥の記録が無い | 外せない |
| fix 型のコミットがあるなら、欠陥の記録がある | fix_without_escape |
| テストの skip の追加や、足した数より多いアサーションの削除が無い | weaken |

リポジトリが hymme の台帳を持っている場合(`tasks/` に loopeng、fv、verifiability、test-design、stages.md、surface.md のどれかがある)は、さらに次も確かめます。表の上から4行は、検証容易性の台帳の「## 対象」のコードがこの変更で変わっている名前だけが対象です(コミットしていない変更と、git が追っていない新しいファイルも「変わっている」に数えます)。

| 確かめること | 例外で外せるか |
|---|---|
| その名前の `verifiability.py` と、その名前でこれまでに実行した検証の入口の種類(`agentloop-middle`、`smt_oracle.py`、`lake build`、`tlc` の直接の実行など。`trace_check.py`、`agentloop-inner`、`agentloop-outer` は除く)を、この変更の ID で実行し直して通っている | stale |
| spec(`.tla`)のある名前は、`<名前>.normal.jsonl`、`.load.jsonl`、`.fault.jsonl` のログが通り、`.broken.jsonl`(わざと壊した実装のログ)が不一致(終了コード 1)になっている。ログは `hymme capture` で採ったもの。| trace |
| spec(`.tla`)のある名前は、状態の図が今の spec から作られ、破れた規則と検査されなかった規則が無く、作業者が承認している | 外せない |
| `.smt.py` のある名前は、突き合わせのコマンドがこの変更の ID で通っている | stale |
| `tasks/stages.md` に段のコマンドの宣言がある | stages |
| `tasks/surface.md` があり、形が整っていて、確認のコマンドがこの変更の ID で通っている | surface |
| PR の本文に「影響の範囲」と「検証」の見出しがある(英語なら Blast Radius か Impact、Verification か Test Plan。本文をコマンドで渡したときだけ見る。`.github/` に PR のテンプレートがあれば見ない) | pr_body |

例外は `hymme exception request <検査> --until YYYY-MM-DD --reason <理由>` で申請し、作業者が承認します。期限は最長90日です。作業者の確認(一覧、状態の図、欠陥の記録)は例外で外せません。

## 段の宣言と欠陥の記録

`tasks/stages.md` の形です。段は spec、unit、integration、e2e、trace、ci の順です。

```markdown
- unit コマンド: `pytest tests/unit`
- unit パス: tests/unit/*
- e2e コマンド: `pytest tests/e2e`
- e2e パス: tests/e2e/*
```

後段のテストが無いリポジトリは段を宣言できないので、`hymme exception request stages` で作業者の承認を取ります。

integration 以降の段のコマンドが失敗すると、hook が欠陥の記録 `tasks/escapes/E<日時>.md` を開きます。ただし、その段のテストをこのブランチで書いている最中(その段のパスに当たるファイルを変更している)なら開きません。閉じていない記録がすでに1件あるときも、新しくは開きません。作業者から報告されたバグや本番の欠陥は `hymme escape open --stage <段> --symptom <症状>` で開きます。

欠陥の記録は、開いたブランチに結び付きます。fix 型のコミットがあるブランチは、そのブランチで開いた記録が1件あれば通ります。

欠陥の記録の欄です。

```markdown
- 症状:
- 見つかった段:
- 拾えたはずの段:
- 抜けた理由:
- 前段に足したテスト:
- テストのコマンド:
- 水平展開:
- 再現のコマンド:
- 修正前のコミット:
- 準備のコマンド:
```

抜けた理由は、要件の抜け、モデルで捨てた領域、手法の選び違い、テストの書き漏れ、検証の弱いテスト、前段では原理的に拾えない、のどれかです。

閉じ方は理由で変わります。

- 手法の選び違い、テストの書き漏れ、検証の弱いテスト: `hymme escape verify <id>` を通す。足したテストのパスが、見つかった段より前の段にあること。足したテストが修正前のコードで失敗し、今のコードで通ること。再現のコマンドがあれば、同じく修正前に失敗し、今は通ること。修正前のコードは一時の worktree に取り出し、足したテストのファイルだけを重ねて実行する。コミットの順は問わない。
- 要件の抜け、モデルで捨てた領域: 要件と確認の一覧を直し、承認を取り直す。記録を開いたあとの一覧の承認が無ければ閉じない。「前段に足したテスト」と「テストのコマンド」の欄は要らない。
- 前段では原理的に拾えない: `hymme escape unreachable <id> --reason <理由>` で申請し、作業者が承認する。この理由でも「前段に足したテスト」と「テストのコマンド」の欄は要らない。承認のあとに記録を変えると、承認は失効する。

どれも、最後に `hymme escape verify <id>` を実行すると、hook が閉じた記録を書きます。コマンドの中で PATH を変えていると、記録しません。

`hymme escape stats` は、抜けた理由ごとの件数を出します。

## 実物の定義

`tasks/surface.md` の形です。

```markdown
## 起動
## 健全性の確認
## 操作
## 証跡
## 後片付け

- 確認のコマンド: `<実物を動かして確かめるコマンドの先頭>`
- 検証と本番で違う値: <容量やタイムアウトなどの一覧。無ければ「無し: 理由」>
```

## hymme コマンドの一覧

| コマンド | すること |
|---|---|
| `hymme claims check <名前>` | 確認の一覧の形を検査する |
| `hymme claims request <名前>` | 一覧の承認を申請する |
| `hymme chart draw <名前>` | TLC を回し、状態の図と規則ごとの結果を `<名前>.chart.md` に書く |
| `hymme chart request <名前>` | 状態の図の承認を申請する |
| `hymme exception request <検査> --until 日付 --reason 理由` | 検査の例外を申請する |
| `hymme escape open --stage 段 --symptom 症状` | 欠陥の記録を手で開く |
| `hymme escape verify <id>` | 欠陥の記録を確かめる(通れば hook が閉じる) |
| `hymme escape unreachable <id> --reason 理由` | 「前段では拾えない」の承認を申請する |
| `hymme escape list` / `hymme escape stats` | 一覧と、抜けた理由ごとの件数 |
| `hymme capture <ログ> -- <コマンド>` | 実システムを動かしてログを採る |
| `hymme specs` | この変更が触れている検証の対象の名前 |

## 限界

- 署名の鍵は作業者のホームにあります。本人が意図して読み出せば、記録を偽造できます。防げるのは、ファイルへ1行足すだけの偽造までです。
- reviewer を起動するのは作業する本人です。reviewer に「合格と書け」と頼めば、合格の記録が書かれます。reviewer の指示文で、依頼文の指示より検査項目を優先させます。
- スクリプトや Makefile の中から呼ばれた検証の入口は、hook から見えません。その実行は記録されないので、統合の入口で「記録が無い」として止まります。
- Web の画面で作った PR は hook から見えません。
- 後段のテストを足しているブランチでは、後段の失敗で欠陥の記録が自動では開きません。既存のテストの退行は手で開きます。
- 名前が `MC` で始まる spec を直接回すと、同じ場所に `MC` を除いた名前の spec があれば、その名前の検証として扱います(前件の到達の確認用)。
