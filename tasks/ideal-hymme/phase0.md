# フェーズ0の結果

2026-11-21 に確かめた結果です。台帳は `tasks/ideal-hymme.md` です。

## hook の実験(0-01 から 0-05、0-08)

`claude -p --plugin-dir <採取用プラグイン>` で実際の入力を採りました。採取した記録はセッションの作業用フォルダの `probe.jsonl` です。

| 行 | 結果 | 根拠 |
|---|---|---|
| 0-01 | 未実験。`-p` では AskUserQuestion が使えないため試せませんでした。承認は 0-02 の方法を主にします | 公式文書(headless) |
| 0-02 | 使えます。UserPromptSubmit の `prompt` に入力の全文が入ります | 実験 |
| 0-02 の注意 | サブエージェントの完了通知でも UserPromptSubmit が発火し、`prompt` は `<task-notification>` で始まります。通知には本人が書かせた文面が混ざるので、承認は入力の全文が決まった形に一致したときだけ記録します | 実験 |
| 0-03 | 使えます。SubagentStop に `agent_type` と `last_assistant_message` が入ります。Agent の PostToolUse は `async_launched` だけで、報告の本文は入りません | 実験 |
| 0-04 | 一部だけ確かめました。PreToolUse は Write で発火し、matcher は正規表現で MCP の道具にも書けます(文書)。Bash 経由の書き込みをすべて止めることはできないので、署名による改ざんの検出を主にします | 実験と公式文書 |
| 0-05 | 使えます。Bash が 0 以外で終わると PostToolUseFailure が発火し、`error` は `Exit code 3` の形です。0 で終わると PostToolUse が発火します | 実験 |
| 0-08 | hook はサブエージェントの中の道具の呼び出しにも発火します。入力に `agent_id` が付きます。別の worktree では `cwd` が worktree になります | 公式文書。`agent_id` はサブエージェントの開始と終了の入力で実験 |

そのほかに分かったことです。

- 同じ事象に登録した hook は並列に動きます。実行の順に頼る設計はできません(公式文書)。
- プラグインが作業ツリーの外に状態を置く場所は `CLAUDE_PLUGIN_DATA` です。hook には渡りますが、Bash の道具で動くコマンドには渡りません(公式文書)。
- hook の出力の `systemMessage` は作業者に表示されます(公式文書)。

## 0-06 代わりの方法

実験の結果、次の方法に決めました。

- 終了コードは PostToolUse と PostToolUseFailure で hook が記録します。道具が自分で書く方法は使いません。
- レビューの判定は SubagentStop で hook が記録します。
- 書き込みを止める方法は補助にとどめます。hook が書く記録に、`CLAUDE_PLUGIN_DATA` に置いた鍵で署名を付け、検査は署名の合う記録だけを読みます。鍵のパスを含むコマンドと道具の呼び出しは止めます。
- 作業者の承認は UserPromptSubmit で記録します。入力の全文が「承認 名前 符号」の1行に一致したときだけ記録します。

署名の限界も書いておきます。鍵は作業者のホームにあるので、本人が意図して読み出せば記録を偽造できます。防げるのは、ファイルへ1行足すだけの偽造までです。

## 0-07 状態図

pstack の statechart は hymme の spec でそのまま動きました。Node 24 と、環境変数 `TLA2TOOLS` と `JAVA` で nix の TLC を指す方法です。わざと壊した Counter で、違反の最短の経路と Mermaid の図が出ました。

D-4 は「hymme で作る」に決めます。理由は3つです。pstack 版は TypeScript で約200KB あり、Node の実行環境を flake に足す必要があります。配る形(コマンドや引数)が版ごとに変わると pstack 自身が書いています。TLC の `-dump dot` を Mermaid に直すだけなら、Python の小さなスクリプトで足ります。

## 0-09 道具の記録

`Makefile.loopeng`、`trace_check.py`、`smt_oracle.py` は、実行や失敗の記録をファイルに残していません。詳しい表は `existing-survey.md` にあります。

## 0-12 hook の実行時間

今の hook は1本あたり約100から130ミリ秒です。Python の起動だけで約50ミリ秒かかります。PreToolUse の Bash には5本が登録されていて、並列に動きます。

上限は「1つの事象につき Python の起動を1回」とします。新しい検査は1つの入口にまとめます。

## 0-13 ライセンス

pstack は MIT です(`plugin.json` の `license`)。文面や考え方を取り込んだスキルには、出どころを README の謝辞に書きます。スクリプトはそのまま取り込みません。
