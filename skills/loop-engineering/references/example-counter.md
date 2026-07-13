# 最小完全例: Counter を 0段→3ループ通す

本題に広げる前に、この最小例が3ループ通ることを必ず確認する(慣らし運転)。
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
| S-003    | R-3        | Inv: c <= N  | test_caps_at_n      |
```

全 ID `[x]`・欠番なし → 0段を閉じて外ループへ。

## 1. 外ループ: EARS + モデル → spec

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

## 2. 中ループ: model-check + mutation

`loop-middle SPEC=Counter`。

- model-check: `No error`(c は 0..3 で Inv を守る)。
- mutation oracle: `c < N`→`c <= N` の変異を注入すると c=N+1 に到達でき Inv 違反 → TLC が killed(捕まえる)。これで「上限ガードが効いている」ことが spec レベルで実証される。survivor が equivalent だけになったら閉じる。

わざとガードを `c < N+1` に弱めて回すと反例が出る → 内ループへ。

## 3. 内ループ: 反例 → Gherkin

ガードを弱めたときの TLC 反例を `trace_to_gherkin.py` が変換:

```gherkin
Scenario: counter must not exceed N
  Given c = 3
  When Inc
  Then c becomes 4   # Inv violated — これは起きてはならない
```

ガードを `c < N` に戻すと反例が消える。設計が固まったら正常系シナリオ(0→1→2→3)を `.feature` に足し、実装の受け入れテストにする。

## 本体への落とし方

`c <= N` と「N でこれ以上増えない」を TDD のテストリストにする(`test_caps_at_n` 等)。
**本体コード・テスト名・コメントに `S-003` や `Inv` や「TLA+」は書かない**(裏方ルール)。振る舞いそのものを説明する。
