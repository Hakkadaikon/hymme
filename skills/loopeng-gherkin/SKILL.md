---
name: loopeng-gherkin
description: >
  loop-engineering の内ループ(受け入れ仕様化)。TLC の反例トレースを Gherkin の Scenario へ機械変換し、
  設計が固まったら正常系の受け入れシナリオを足して実装のテストへ橋渡しする。
  「反例を Gherkin に」「受け入れ仕様に落として」「feature ファイルにして」と言われたとき、
  または loop-engineering ルーターから内ループとして委譲されたときに使用する。
  前提: loopeng-modelcheck の TLC 実行結果(反例トレース、または No error)があること。
  無ければ先に loopeng-modelcheck へ戻る。通常は loop-engineering ルーターの判断を通ってから使う。
---

# loopeng-gherkin (内ループ: TLC の反例を Gherkin の受け入れ仕様へ)

`Inv` を破る反例は、設計レベルのバグであり**実行可能な反例**でもある。
`loop-inner SPEC=<Name>` で TLC のエラートレースを `<Name>.feature` の Gherkin Scenario に変換(`trace_to_gherkin.py`。駆動装置は [`../_shared/loopeng-toolchain.md`](../_shared/loopeng-toolchain.md))。
**前提**: loopeng-modelcheck の実行結果があること。無ければ **loopeng-modelcheck** へ戻る。

- 初期状態 = `Given`、各アクション = `When`、変化した変数 = `Then becomes ...`。
- この feature は「起きてはならない」失敗例。設計を直して反例が消えるまで外(**loopeng-formalize**)/中(**loopeng-modelcheck**)ループへ戻す。
- 設計が固まったら、正の受け入れシナリオ(EARS 正常系)を `.feature` に足し、実装の受け入れテストにする。
  トレーサビリティ・マトリクスの「テスト」列へ消し込む。TLC 反例由来は機械変換で消し込み不要(1反例=1 feature)。「テスト」列が空の event/state 系 EARS 正常系=このループの漏れ。

> 生成 `.feature` を実行可能テストにする配線(言語別 OSS ランナー、C の例外、緑/赤での生死実証)は [`references/gherkin-runners.md`](references/gherkin-runners.md)。

## やらないこと

- 生成 `.feature` を手編集しない。源泉(spec / EARS)を直して再生成する。
- 反例由来のテストへ「TLA+ 反例由来」等の痕跡を書かない。振る舞いそのものを説明する([`../_shared/stealth-artifacts.md`](../_shared/stealth-artifacts.md))。
- 機能レベルのテスト展開(同値分割・境界値・property-based の選定)まで抱え込まない。そこは test-design スキル系の担当。

## 次の工程

反例が尽き、正常系シナリオまで足せたら loop-engineering ルーターへ戻り、完了前ゲート(reviewer 委譲)と実装への橋渡し([`../loop-engineering/references/bridging.md`](../loop-engineering/references/bridging.md))へ進む。
