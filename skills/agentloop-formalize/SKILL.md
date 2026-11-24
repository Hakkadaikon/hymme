---
name: agentloop-formalize
disable-model-invocation: true
description: >
  agent-loop の外ループ(要求形式化)。抽出済みの要件を EARS 記法 + 状態/ドメインモデルへ構造化し、
  TLA+ spec(<Name>.tla / <Name>.cfg)と Gherkin の骨格(<Name>.feature)を書く。
  「EARS に落として」「状態モデルを作って」「TLA+ spec を書いて」「要求を形式化」と言われたとき、
  または agent-loop ルーターから外ループとして委譲されたときに使用する。
  前提: agentloop-extract の抽出台帳(tasks/loopeng/<Name>.extract.md)が完成(全 ID `[x]`・欠番なし・閉じる前のチェックが全項目埋まっている)していること。
  無ければ先に agentloop-extract へ戻る。通常は agent-loop ルーターの判断を通ってから使う。
---

# agentloop-formalize (外ループ: NL を EARS + 状態/ドメインモデルへ)

抽出した要件(または最初から自然言語の要求)を2つに構造化する。曖昧な点はモデル化前にユーザーへ確認。
**前提**: `tasks/loopeng/<Name>.extract.md` の台帳が閉じていること。無い/未完なら **agentloop-extract** へ戻る。`tasks/verifiability/<Name>.md` の検証容易性の台帳が通っていること([`../verifiability/SKILL.md`](../verifiability/SKILL.md) の「強制のしくみ」)。
EARS とモデルを書いたら、spec を書く前に確認の一覧をユーザーに承認してもらう(下の「ユーザーの確認」)。

## EARS 記法

各要求を1文ずつ。型を取り違えない:

- ubiquitous: 「The <system> SHALL <response>.」(常時の義務)
- event: 「WHEN <trigger> the <system> SHALL <response>.」
- state: 「WHILE <state> the <system> SHALL <response>.」
- unwanted: 「IF <condition> THEN the <system> SHALL <response>.」(異常系)
- optional: 「WHERE <feature> the <system> SHALL <response>.」

基本5パターンで書けない(多条件・ロール別分岐・優先順位・定量化 NFR)、または変換前の弱点の確認や
書き上げ後のセルフレビューが要るときは [`references/ears-patterns.md`](references/ears-patterns.md) を使う。

### EARS 本体の行数

EARS 本体の行数制約(1 文あたりソース行で1〜2行)と、補足を「設計メモ」節へ分離する規範は
[`../agentloop-extract/SKILL.md`](../agentloop-extract/SKILL.md) の手順4を参照(定義はそちらが一次ソース)。
0 段で抽出した台帳をそのまま使う場合は既に満たされているはずだが、formalize 段で EARS 文を
書き直す/追記するときも同じ制約が適用される。

## 状態/ドメインモデル

名詞=状態変数、各変数の型(値域)、初期状態、不変条件。各 EARS 節がどの状態遷移に対応するかを対応づける。

**モデル化で捨てた領域を明示する(抽象化の死角対策)**: 状態機械に不要な詳細(値の内部表現、エンコーディング形式、
個々のフィールドの妥当性)を捨てるのは正しい設計判断だが、**捨てた領域は TLC の検査範囲に原理的に入らない**。
モデル化の際、「この変数・このフィールドは状態機械の外側で別途検証する」と決めた箇所を 0 段の台帳に
一言残す(トレーサビリティ・マトリクスの備考、または台帳の該当行)。書き残さないと、その領域は
どの層でも検証されないままになる([`../agentloop-extract/references/lessons.md`](../agentloop-extract/references/lessons.md) の抽象化の死角)。

**安全性に関わる unwanted 要件(「IF 対象要素が X に分類されるとき拒否する」等)を値域だけの抽象定数
(`X \subseteq Elements` 等)で表した場合は「一言」では足りない**。`Inv`(`visited ∩ X = {}` 等)が検査するのは
「ガードが働くこと」だけで、「ある要素が実際に X に分類されるべきか」という判定ロジック自体の正しさは
検査していない。この種の抽象定数については、上記と同じ記録先(0段台帳のトレーサビリティ・マトリクス備考、
または台帳の該当行)に、それぞれ (a) 実装時にどう判定するか(キーワード/役割/URL パターン等の判定軸)、
(b) その判定ロジック自体をどう検証するか(ゴールデンテスト・ファジング・差分テスト等、TLC 以外の手段)の
2点を明記する。
TLC が "No error" を返しても、それは「抽象化した集合の中でガードが働く」ことしか保証しない。

## ユーザーの確認(EARS を書いた直後、spec を書く前)

EARS を書き、モデルの値域と捨てる領域を決めたら、spec を書く前に**確認の一覧**を作ってユーザーの承認を取る。検証で何を示し、何を示さないかを、検証の前にユーザーが判断するための一覧。承認が無いと `agentloop-outer` を含む検証の入口はすべて hook に止められる。

1. [`assets/claims-template.md`](assets/claims-template.md) を `tasks/loopeng/<Name>.claims.md` にコピーする。
2. 「## 実証する項目」に、EARS の1行ごとに表の1行を書く。「要件」は EARS を平文に直した1文、「示すこと」は検証が示すこと、「示さないこと」は検証が示さないこと、「破れたときの害」は破れると誰がどう困るかを、それぞれ1文で書く。
3. 「## 有限にした範囲」に、検証のために有限にした上限や値の範囲(`CONSTANT` に入れる値。最大3接続、キュー長2など)を書く。無ければ「無し: 理由」。
4. 「## 扱わない領域」に、上の「モデル化で捨てた領域」を0段の台帳の備考から写し、それを別にどう確かめるかを添える。無ければ「無し: 理由」。
5. 「## 置いた仮定」に、検証が前提にしたことを書く。モデルの外の仕組み(外部のシステム、設定の値、呼び出す側)がどう振る舞うと仮定したか、実物でそれが成り立つ根拠は何か、の2つである。仮定が実物より狭いと、実物で起きる振る舞いを検査から漏らす。無ければ「無し: 理由」。「いつかは起きる」を示すために公平性(実行できる操作は、いつかは実行される)を仮定するなら、「公平性」で始まる行を書く。spec に `WF_` か `SF_` があるのにこの行が無いと、`hymme claims request` と検証の入口が止める。ひな形の spec は `WF_vars(Next)` を含むので、「いつかは起きる」を示さない設計では spec から外す。
6. 「## 防ぎたいバグの種類」に、ユーザーと挙げたバグや脆弱性の種類と、表のどの行がそれを防ぐかを書く。手順は [`../_shared/detection-scope.md`](../_shared/detection-scope.md)。この節は形の検査の対象ではない。
7. **手法の用語と管理番号を書かない**。TLA+、TLC、EARS、SMT、Z3、Lean、`Inv`、`S-001`、不変条件、モデル検査、mutation などが入っていると形の検査で落ちる。ユーザーが検証の言語を知らなくても判断できる日本語の平文にする。表のセルと下の節の行には `<` も書かない。ひな形の書きかけ(`<…>`)と区別できず、空の扱いで落ちる。大小は「未満」「より小さい」と書く。
8. `hymme claims request <Name>` を実行する。形を検査し、申請を作る(形だけ見るなら `hymme claims check <Name>`)。hook が一覧のファイルの中身と承認コードをユーザーに表示する。エージェントの要約ではなく、ファイルの中身そのものが出る。
9. ユーザーが `承認 <承認コード>` とだけ入力すると、hook が承認を記録する。承認の入力はユーザーだけができる。この文字列をツールの入力に入れても記録されず、止められる。

承認のあとに一覧を1文字でも変えると、承認は失効する。ユーザーが項目を直したいと言ったとき、またはあとの工程で要件・値域・捨てる領域・置いた仮定が変わったときは EARS、モデル、一覧の順に作り直し、`hymme claims request <Name>` で承認を取り直す。一覧だけを直して源泉(EARS + モデル)と食い違わせない。

一覧を作って承認を取るのはコントローラ。サブエージェント(modeler)や無人の実行ではユーザーが入力できないので、承認が無ければ着手せず BLOCKED で返す。modeler へ委譲するなら、承認を取ってから dispatch する。

## TLA+ spec への落とし込み

`agentloop-outer SPEC=<Name>` でテンプレから `<Name>.tla`/`<Name>.feature` を scaffold(既存は壊さない。実行するツールは [`../_shared/agentloop-toolchain.md`](../_shared/agentloop-toolchain.md))。EARS とモデルから埋める。

- `VARIABLES` = 状態変数。`TypeOK` = 各変数の型(値域)を `\in` で(網羅性のアンカー)。`Init` = 初期状態。
- `Next` = **EARS の各 event/state/unwanted 節を 1 disjunct** に。`\/ Action1 \/ Action2 ...`。1節1アクション。
- `Inv` = ubiquitous /「SHALL never」を安全性に。応答義務・到達性が要るなら `<>`/`[]` で別途。

`<Name>.cfg` に `INIT`/`NEXT`/`INVARIANT`(必要なら `CONSTANT` で状態空間を絞る)。`CONSTANT` の値は確認の一覧の「有限にした範囲」と同じにする。

最小の書き方の完全例(Counter)は [`../agent-loop/references/example-counter.md`](../agent-loop/references/example-counter.md)。

## 消し込みと置き場

- 台帳の R 番号と `Next` disjunct / `Inv` の対応をトレーサビリティ・マトリクスの「形式手法」列へ消し込む。空欄の EARS 行=外ループの漏れ。
- 成果物は `tasks/loopeng/` 配下・git 管理外([`../_shared/stealth-artifacts.md`](../_shared/stealth-artifacts.md))。

## やらないこと

- 生成物(`.tla`/`.feature`)を手編集して源泉(EARS + モデル)と乖離させない。源泉を直して再生成する。

## 次の工程

spec が書けたら **agentloop-modelcheck** スキルで TLC のモデル検査と mutation oracle を実行する。
