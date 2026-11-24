# 最小完全例: Counter を 0段→3ループ通す

本題に広げる前に、この最小例で3ループを最後まで実行できることを必ず確認する。
要件は「0 から始まり、上限 N まで 1 ずつ増える。N を超えない」だけ。

## 0段: 抽出台帳(`tasks/loopeng/Counter.extract.md`)

口頭要求しか無いので、その要求文を台帳の起点にする。

```
## 台帳
- [x] S-001 「カウンタは 0 から始まる」
      → The system SHALL initialize the counter to 0. (ubiquitous)
- [x] S-002 「1 ずつ増える」
      → WHEN incremented the system SHALL add 1 to the counter. (event)
- [x] S-003 「上限 N を超えない」
      → IF the counter is N THEN the system SHALL NOT increment. (unwanted)

## トレーサビリティ
| 仕様条項 | 要件(EARS) | 形式手法     | テスト              |
|----------|------------|--------------|---------------------|
| S-001    | R-1        | Init         | test_starts_at_zero |
| S-002    | R-2        | Inc disjunct | test_increments     |
| S-003    | R-3        | Inc のガード `c < N` / Inv `c <= N` | test_caps_at_n |
```

「閉じる前のチェック」の信頼境界は「無し: 外部入力を受けない内部カウンタ」、STRIDE 6行は各行「該当なし: 信頼境界無し」、CWE は「パース・算術無し: 入力を持たず、長さ・オフセットの算術も無い」と書く。やり直しと並行の3行は増やす操作について「2回実行したとき: 該当なし: 2回増やせば 2 増えるのが要求どおり」のように1行ずつ埋める。境界と失敗時の意味論の各行も、上限のガードについて S-ID か「該当なし: 理由」で埋める。「閉じる前のチェック」に未チェック(`- [ ]`)か空の行が残ると、検証の入口は hook に止められる。

全 ID `[x]`・欠番なし、閉じる前のチェックも全項目埋まった → 0段を閉じて外ループへ。

写すコードがまだ無いので、検証容易性の台帳(`tasks/verifiability/Counter.md`)は「## 対象」を `対象コード無し: 設計だけの最小例` の1行にして作る。台帳が無いと検証の入口は止まる。

## 1. 外ループ: EARS + モデル → spec

spec を書く前に、確認の一覧(`tasks/loopeng/Counter.claims.md`)を作る。手法の用語と管理番号は書かない。

```markdown
# Counter で確かめること

## 実証する項目

| 要件 | 示すこと | 示さないこと | 破れたときの害 |
|---|---|---|---|
| カウンタは 0 から始まる | 最初の値が 0 である | 再起動のあとに 0 へ戻ること | 前回の値が残り、数え間違う |
| 1 ずつ増える | 1回の操作で値が 1 だけ増える | 2つの操作が同時に来たときの結果 | 値を飛ばして数える |
| 上限を超えない | どの順で操作しても値が上限以下である | 上限が 3 より大きいときの振る舞い | 上限を超えた値が後続の処理に渡る |

## 有限にした範囲

- 上限は 3 で確かめる

## 扱わない領域

- 値の保存と表示。別に単体テストで確かめる

## 置いた仮定

- 無し: 「いつかは起きる」を示す項目が無く、外の仕組みにも前提を置かない

## 防ぎたいバグの種類

- 上限を超えて数える: 「上限を超えない」の行が防ぐ
- 2つの操作が同時に来て数え間違う: 未検証。結合テストで確かめる
```

`hymme claims request Counter` を実行し、表示された `承認 <承認コード>` の1行をユーザーに入力してもらう。承認が記録されるまで `agentloop-outer` は止まる。

状態変数は `c`(カウンタ)、定数は `N`。`Counter.tla`:

```tla
---- MODULE Counter ----
EXTENDS Naturals
CONSTANT N
VARIABLE c
Init == c = 0                          \* S-001
Inc  == c < N /\ c' = c + 1            \* S-002 + S-003(ガード c < N)
Next == Inc
Inv  == c <= N                         \* S-003 を安全性に
====
```

`Counter.cfg`:

```
CONSTANT N = 3
INIT Init
NEXT Next
INVARIANT Inv
```

## 2. 中ループ: model-check + mutation + 文面の往復確認

`agentloop-middle SPEC=Counter`。

- model-check: `No error`(c は 0..3 で Inv を守る)。
- mutation oracle: `c < N`→`c <= N` の変異を注入すると c=N+1 に到達でき Inv 違反 → TLC が killed(検出する)。これで「上限ガードが働いている」ことが spec レベルで実証される。survivor が equivalent だけになったら閉じる。
- 文面の往復確認: `Init`・`Inc`・`Inv` だけ(コメントの `\* S-00x` は消す)を `Counter.faithfulness-input.md` に写し、別の subagent に平文へ戻させる。言い直しは「c は 0 で始まる」(`Init`)、「c が N 未満のときだけ 1 増やす」(`Inc`)、「c は常に N 以下」(`Inv`)。R-1 は `Init` で `full`。R-2「1 ずつ増える」は `Inc` の増分で `full`。R-3「N のとき増やさない」は遷移の禁止なので、担うのは `Inc` のガード `c < N` で、`Inv` はその帰結にすぎない。式欄に `Inc` のガードと `Inv` を併記して `full` とする(`Inv` だけを当てるなら `partial` で、理由欄に「ガードで担保」と書く)。`Counter.faithfulness.md` にこの 3 行を記録する。含意の不変条件が無いので空成立の確認は要らない。
- 状態遷移図: `hymme chart draw Counter` が `Counter.chart.md` に図と規則ごとの結果を書く(到達した状態は c = 0..3 の 4 つ、破れた規則はなし)。`hymme chart request Counter` でユーザーの承認を取る。

内ループを体験するためのデモとして、わざとガードを `c < N+1` に弱めて実行すると反例が出る → 内ループへ。

## 3. 内ループ: 反例 → Gherkin

ガードを弱めたときの TLC 反例を `trace_to_gherkin.py` が変換:

```gherkin
Scenario: counter must not exceed N
  Given c = 3
  When Inc
  Then c becomes 4   # Inv violated — これは起きてはならない
```

ガードを `c < N` に戻すと反例が出なくなる。設計が確定したら正常系シナリオ(0→1→2→3)を `.feature` に足し、実装の受け入れテストにする。

## 本体への落とし方

`c <= N` と「N でこれ以上増えない」を TDD のテストリストにする(`test_caps_at_n` 等)。
**本体コード・テスト名・コメントに `S-003` や `Inv` や「TLA+」は書かない**(「痕跡を残さない」規範)。振る舞いそのものを説明する。
