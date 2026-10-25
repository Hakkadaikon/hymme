---
name: loopeng-formalize
description: >
  loop-engineering の外ループ(要求形式化)。抽出済みの要件を EARS 記法 + 状態/ドメインモデルへ構造化し、
  TLA+ spec(<Name>.tla / <Name>.cfg)と Gherkin の骨格(<Name>.feature)に落とす。
  「EARS に落として」「状態モデルを作って」「TLA+ spec を書いて」「要求を形式化」と言われたとき、
  または loop-engineering ルーターから外ループとして委譲されたときに使用する。
  前提: loopeng-extract の抽出台帳(tasks/loopeng/<Name>.extract.md)が完成(全 ID `[x]`・欠番なし・閉じる前のチェックが全項目埋まっている)していること。
  無ければ先に loopeng-extract へ戻る。通常は loop-engineering ルーターの判断を通ってから使う。
---

# loopeng-formalize (外ループ: NL を EARS + 状態/ドメインモデルへ)

抽出した要件(または最初から自然言語の要求)を2つに構造化する。曖昧な点はモデル化前にユーザーへ確認。
**前提**: `tasks/loopeng/<Name>.extract.md` の台帳が閉じていること。無い/未完なら **loopeng-extract** へ戻る。`tasks/verifiability/<Name>.md` の検証容易性の台帳が通っていること([`../verifiability/SKILL.md`](../verifiability/SKILL.md) の「強制のしくみ」)。

## EARS 記法

各要求を1文ずつ。型を取り違えない:

- ubiquitous: 「The <system> SHALL <response>.」(常時の義務)
- event: 「WHEN <trigger> the <system> SHALL <response>.」
- state: 「WHILE <state> the <system> SHALL <response>.」
- unwanted: 「IF <condition> THEN the <system> SHALL <response>.」(異常系)
- optional: 「WHERE <feature> the <system> SHALL <response>.」

基本5パターンで書けない(多条件・ロール別分岐・優先順位・定量化 NFR)、または変換前の弱点洗い出しや
書き上げ後のセルフレビューが要るときは [`references/ears-patterns.md`](references/ears-patterns.md) を使う。

### EARS 本体の行数

EARS 本体の行数制約(1 文あたりソース行で1〜2行)と、補足を「設計メモ」節へ分離する規範は
[`../loopeng-extract/SKILL.md`](../loopeng-extract/SKILL.md) の手順4を参照(定義はそちらが一次ソース)。
0 段で抽出した台帳をそのまま使う場合は既に満たされているはずだが、formalize 段で EARS 文を
書き直す/追記するときも同じ制約が適用される。

## 状態/ドメインモデル

名詞=状態変数、各変数の型(値域)、初期状態、不変条件。各 EARS 節がどの状態遷移に対応するかを対応づける。

**モデル化で捨てた領域を明示する(抽象化の死角対策)**: 状態機械に不要な詳細(値の内部表現、エンコーディング形式、
個々のフィールドの妥当性)を捨てるのは正しい設計判断だが、**捨てた領域は TLC の検査範囲に原理的に入らない**。
モデル化の際、「この変数・このフィールドは状態機械の外側で別途検証する」と決めた箇所を 0 段の台帳に
一言残す(トレーサビリティ・マトリクスの備考、または台帳の該当行)。書き残さないと、その領域は
どの層でも検証されないまま消える([`../loopeng-extract/references/lessons.md`](../loopeng-extract/references/lessons.md) の抽象化の死角)。

**安全性に関わる unwanted 要件(「IF 対象要素が X に分類されるとき拒否する」等)を値域だけの抽象定数
(`X \subseteq Elements` 等)に丸めた場合は「一言」では足りない**。`Inv`(`visited ∩ X = {}` 等)が検査するのは
「ガードが効くこと」だけで、「ある要素が実際に X に分類されるべきか」という判定ロジック自体の正しさは
検査していない。この種の抽象定数については、上記と同じ記録先(0段台帳のトレーサビリティ・マトリクス備考、
または台帳の該当行)に、それぞれ (a) 実装時にどう判定するか(キーワード/役割/URL パターン等の判定軸)、
(b) その判定ロジック自体をどう検証するか(ゴールデンテスト・ファジング・差分テスト等、TLC 以外の手段)の
2点を明記する(「一言」で済む通常の捨てた領域より詳しく書く必要がある、という違いだけで記録先は同じ)。
TLC が "No error" を返しても、それは「抽象化した集合の中でガードが効く」ことしか保証しない。

## TLA+ spec への落とし込み

`loop-outer SPEC=<Name>` でテンプレから `<Name>.tla`/`<Name>.feature` を scaffold(既存は壊さない。駆動装置は [`../_shared/loopeng-toolchain.md`](../_shared/loopeng-toolchain.md))。EARS とモデルから埋める。

- `VARIABLES` = 状態変数。`TypeOK` = 各変数の型(値域)を `\in` で(網羅性のアンカー)。`Init` = 初期状態。
- `Next` = **EARS の各 event/state/unwanted 節を 1 disjunct** に。`\/ Action1 \/ Action2 ...`。1節1アクション。
- `Inv` = ubiquitous /「SHALL never」を安全性に。応答義務・到達性が要るなら `<>`/`[]` で別途。

`<Name>.cfg` に `INIT`/`NEXT`/`INVARIANT`(必要なら `CONSTANT` で状態空間を絞る)。

最小の書き方の完全例(Counter)は [`../loop-engineering/references/example-counter.md`](../loop-engineering/references/example-counter.md)。

## 消し込みと置き場

- 台帳の R 番号と `Next` disjunct / `Inv` の対応をトレーサビリティ・マトリクスの「形式手法」列へ消し込む。空欄の EARS 行=外ループの漏れ。
- 成果物は `tasks/loopeng/` 配下・git 管理外([`../_shared/stealth-artifacts.md`](../_shared/stealth-artifacts.md))。

## やらないこと

- 生成物(`.tla`/`.feature`)を手編集して源泉(EARS + モデル)と乖離させない。源泉を直して再生成する。

## 次の工程

spec が書けたら **loopeng-modelcheck** スキルで TLC のモデル検査と mutation oracle を回す。
