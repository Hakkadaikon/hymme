# ブラックボックス設計技法（組合せの縮約）

条件や因子の組合せが爆発するとき、それを縮約してテストを導く技法群。
ブラックボックス技法のうち入力空間の分割と履歴(同値分割、境界値分析、デシジョンテーブル、状態遷移)は [`blackbox-systematic.md`](blackbox-systematic.md) に置く。
ここでは、複数の条件や因子が掛け合わさってケース数が指数的に膨れる場面を扱い、論理関係や2要因被覆や分類軸で全数を縮める技法をまとめる。

これらも独立して使うものではなく、入力空間の分割技法の上に重ねる。
条件の論理関係が複雑なら原因結果グラフ、独立した因子が多くて全組合せが爆発するならペアワイズ、入力が複数の側面を持つならクラシフィケーションツリーへ進む。

## 目次

- [原因結果グラフ(Cause-Effect Graph)](#原因結果グラフcause-effect-graph)
- [ペアワイズ/直交表(Pairwise / All-pairs)](#ペアワイズ直交表pairwise--all-pairs)
- [クラシフィケーションツリー法(Classification Tree Method)](#クラシフィケーションツリー法classification-tree-method)

---

## 原因結果グラフ(Cause-Effect Graph)

### 概要

入力条件(原因)と出力(結果)を論理ゲート(AND/OR/NOT)で結んだグラフを描き、そこから機械的にデシジョンテーブルを導出する。

### 目的/いつ使う

条件と結果の論理関係が複雑で、デシジョンテーブルを手で作ると組合せを取りこぼす恐れがあるときに使う。
グラフ化すれば論理の矛盾や冗長を先に発見できる。
関係が単純ならグラフは省き、直接デシジョンテーブルでよい(YAGNI)。

### TypeScript example

原因結果グラフ自体は設計の中間成果物で、最終的にはデシジョンテーブルへ落ちる。
そのテーブルを「デシジョンテーブル」と同じ `it.each` 形式でテストする。
グラフから導いた論理式をコメントで残すと追跡しやすい。

```ts
import { describe, it, expect } from "vitest";
import { canWithdraw } from "./atm";

// cause-effect:
//   C1 = カード有効, C2 = 残高>=金額, C3 = 1日上限内
//   E(出金可) = C1 AND C2 AND C3
describe("canWithdraw: derived from cause-effect graph", () => {
  const t = true, f = false;
  const cases = [
    { c1: t, c2: t, c3: t, expected: true },
    { c1: f, c2: t, c3: t, expected: false },
    { c1: t, c2: f, c3: t, expected: false },
    { c1: t, c2: t, c3: f, expected: false },
  ] as const;

  it.each(cases)(
    "card=$c1 funds=$c2 limit=$c3 -> $expected",
    ({ c1, c2, c3, expected }) => {
      expect(canWithdraw(c1, c2, c3)).toBe(expected);
    },
  );
});
```

### 落とし穴

- グラフ作成のコストが高い。論理が単純な場面に持ち込むと、得るものより手間が勝つ。
- 制約(原因間の排他、包含)をグラフに書き落とすと、実現不可能な組合せをテストしてしまう。

### 網羅の定義

- **網羅基準**：グラフから導出したデシジョンテーブルの実現可能な全ルールを網羅したとき完了(デシジョンテーブルの基準を継承する)。
- **網羅手順**：
  1. 原因と結果を論理ゲート(AND/OR/NOT)でグラフ化する。
  2. 原因間の制約(排他、包含)をグラフへ反映する。
  3. グラフを機械的にデシジョンテーブルへ変換する。
  4. 残った各ルールを1ケースにする。
- **達成チェック**：制約で実現不可になる組合せをテストに混ぜていないか確認する。

---

## ペアワイズ/直交表(Pairwise / All-pairs)

### 概要

多数のパラメータの全組合せではなく、任意の2パラメータのすべての値の対(ペア)が少なくとも1度現れる最小集合に絞る。
多くの欠陥が2要因の相互作用で起きるという経験則に依拠する。

### 目的/いつ使う

独立した設定項目が多くて全組合せが爆発するときに使う(OS × ブラウザ × 言語 × 通貨など)。
3要因以上の相互作用が疑われる箇所には不向きで、その部分だけ高次の網羅を別途用意する。

### TypeScript example

ペアワイズの組合せ生成はツール(`@fast-check/...` や allpairs 系)で作るのが筋。
ここでは生成済みのペアワイズ表をテストデータとして読み込み回す形を示す。

```ts
import { describe, it, expect } from "vitest";
import { render } from "./checkout";
import pairs from "./checkout.pairwise.json"; // ツールで生成した最小組合せ表

describe("checkout: pairwise coverage", () => {
  it.each(pairs)("%o renders without error", (combo) => {
    expect(() => render(combo)).not.toThrow();
  });
});
```

### 落とし穴

- 「2要因で十分」は経験則。既知の3要因バグがあるなら、その組はペアワイズと別に明示追加する。
- 手で最小集合を組もうとしない。最小化は組合せ最適化で、ツールに任せる。

### 網羅の定義

- **網羅基準**：任意の2パラメータ間の全値ペアが少なくとも1度現れたとき網羅完了(2-way カバレッジ100%)。
- **網羅手順**：
  1. パラメータとその値域を列挙する。
  2. 実現不可な値の組合せを制約として定義する。
  3. covering array をツールで生成する。
  4. 生成表の各行を1ケースにする。
- **達成チェック**：既知の3要因バグがペアワイズと別に明示追加されているか確認する。
- 組合せ生成が手作業でなくツール出力になっているか(手で組むとペア漏れが残る)を見る。

---

## クラシフィケーションツリー法(Classification Tree Method)

### 概要

テスト対象の入力をいくつかの分類(classification)に分け、各分類を同値クラスへ細分してツリーで可視化し、ツリーの葉の組合せからテストケースを選ぶ。
同値分割を多次元へ構造化したものである。

### 目的/いつ使う

入力が複数の独立した側面を持ち、各側面ごとに区分が要るときに使う(画像処理での、フォーマット × サイズ × カラーモードなど)。
ツリーで網羅状況を見ながら、ペアワイズなどと組み合わせて組合せ数を制御できる。
側面が1つなら単なる同値分割で足りる。

### TypeScript example

分類(フォーマット、サイズ)とその葉を配列で持ち、選んだ組合せを `it.each` で回す。
ツリーは設計図、テストはその葉の選択にあたる。

```ts
import { describe, it, expect } from "vitest";
import { thumbnail } from "./image";

// classification tree:
//   format: [png, jpeg, webp]
//   size:   [empty, small, huge]
const selected = [
  { format: "png", size: "small", ok: true },
  { format: "jpeg", size: "huge", ok: true },
  { format: "webp", size: "empty", ok: false },
] as const;

describe("thumbnail: classification tree leaves", () => {
  it.each(selected)("$format/$size -> ok=$ok", ({ format, size, ok }) => {
    expect(thumbnail(format, size).ok).toBe(ok);
  });
});
```

### 落とし穴

- 分類が直交していない(side effect で絡む)と葉の組合せが誤誘導になる。分類軸の独立性を先に確かめる。
- 葉を全組合せで取ると爆発する。ペアワイズや優先度で間引く。

### 網羅の定義

- **網羅基準**：選んだ組合せ戦略(全葉単独、2-way、優先度)に対し、その戦略が要求する葉の選択をすべて踏んだとき網羅完了。
- **網羅手順**：
  1. 入力を独立した分類軸へ分ける。
  2. 各軸を同値クラスへ細分する。
  3. ツリーの葉を列挙する。
  4. 組合せ戦略を選び、その戦略に従って葉の組合せを選択し1ケースずつにする。
- **達成チェック**：分類軸どうしの独立性が確かめてあるか確認する。
- 葉の全組合せが爆発する場合、戦略(ペアワイズ、優先度)で間引けているかを見る。

---

入力空間の分割と状態遷移は [`blackbox-systematic.md`](blackbox-systematic.md) を参照。
