---
name: blackbox-partition
description: >
  内部実装を見ず、入出力仕様だけから入力空間の分割でテストケースを機械的に導くブラックボックス技法群。
  test-catalog の手法カタログの一部。同値分割(Equivalence Partitioning)、境界値分析(Boundary Value Analysis)、
  ドメイン分析テスト(Domain Analysis、多変数の境界on/off/in/out)、デシジョンテーブル(Decision Table、条件の組合せとアクション)
  を検証したい、または割り当てたいときに使う。通常は test-catalog スキルの索引経由で
  手法が選定された後にこのスキルを直接参照する。
disable-model-invocation: true
---

# ブラックボックス設計技法(入力空間の分割)

内部実装を見ず、入出力仕様だけからテストケースを機械的に導く体系的技法群。
ISO/IEC/IEEE 29119-4 はこれらを「仕様ベースのテスト設計技法(specification-based techniques)」として体系化している。
コードを開かずに何を確かめるべきかを決められるので、実装前(TDD のテストリスト)にも有効。

ここでは入力空間の分割を扱う技法(同値分割、境界値分析、ドメイン分析、デシジョンテーブル)をまとめる。
履歴と状態に依存する技法(状態遷移、CRUD / エンティティライフサイクル)は [`blackbox-state.md`](../blackbox-state/SKILL.md) を参照。
条件や因子の組合せが爆発するときにそれを縮約する技法のうち論理ベース(原因結果グラフ、クラシフィケーションツリー)は [`blackbox-cause-effect.md`](../blackbox-cause-effect/SKILL.md) を、因子被覆(ペアワイズ、直交表、T-way)は [`blackbox-covering.md`](../blackbox-covering/SKILL.md) を参照。
経験と直感に依る非形式的な技法のうち、業務フロー起点(ユースケース、シナリオ、構文テスト)は [`experience-scenario.md`](../experience-scenario/SKILL.md) を、経験起点(チェックリスト、エラー推測)は [`experience-checklist.md`](../experience-checklist/SKILL.md) を、乱数・即興起点(ランダムファジング、探索的、アドホック)は [`experience-exploratory.md`](../experience-exploratory/SKILL.md) を参照。

各手法は独立ではなく重ねて使う。
まず同値分割で入力空間を割り、境界値で割れ目を攻め、条件の組合せはデシジョンテーブル、振る舞いの履歴依存は状態遷移、という順で必要なものだけ足す。

## 目次

- [同値分割(Equivalence Partitioning)](#同値分割equivalence-partitioning)
- [境界値分析(Boundary Value Analysis)](#境界値分析boundary-value-analysis)
- [ドメイン分析テスト(Domain Analysis)](#ドメイン分析テストdomain-analysis)
- [デシジョンテーブル(Decision Table)](#デシジョンテーブルdecision-table)

---

## 同値分割(Equivalence Partitioning)

### 概要

入力(または出力)の定義域を、同じように扱われるはずの部分集合(同値クラス)に分割し、各クラスから代表値を1つだけ選ぶ。

### 目的/いつ使う

入力空間が広く全数テストが不可能なとき、代表値で網羅率を保ちつつケース数を圧縮する。
有効クラスと無効クラスの両方を出すのが要点。
クラス内の値が本当に等価かが疑わしいとき(分岐が値ごとに違うときなど)は使わず、境界値やデシジョンテーブルへ進む。

### TypeScript example

年齢区分関数の同値クラス(子供 0-12、大人 13-64、高齢 65+、無効 <0)を代表値で回す。

```ts
import { describe, it, expect } from "vitest";
import { classifyAge } from "./age";

describe("classifyAge: equivalence partitions", () => {
  const cases = [
    { partition: "child", value: 5, expected: "child" },
    { partition: "adult", value: 30, expected: "adult" },
    { partition: "senior", value: 70, expected: "senior" },
    { partition: "invalid", value: -1, expected: "invalid" },
  ] as const;

  it.each(cases)("$partition ($value) -> $expected", ({ value, expected }) => {
    expect(classifyAge(value)).toBe(expected);
  });
});
```

### 落とし穴

- 無効クラス(範囲外、型違い、空)を出し忘れ、正常系だけになる。
- 等価とみなした値が実装上は別経路をたどり、1代表では漏れる。区分の根拠は仕様であって願望ではない。

### 網羅の定義

- **網羅基準**：全有効同値クラスから各1代表、かつ全無効同値クラスから各1代表を踏んだとき網羅完了。
- **網羅手順**：
  1. 入力(と出力)の定義域を、同じ扱いを受けるはずの部分集合へ分割する。
  2. 各クラスを有効(仕様が受理)と無効(範囲外、型違い、空)に仕分ける。
  3. 各クラスから代表値を1つ選び、1ケースにする。
- **達成チェック**：代表が割り当たっていないクラスが0であることを確認する。
- 無効クラス(下限未満、上限超、null、空、型不正)を出し忘れて正常系だけになっていないか見る。

---

## 境界値分析(Boundary Value Analysis)

### 概要

同値クラスの境界に欠陥が集中するという経験則に基づき、各境界の直前、境界上、直後の値を狙う。

### 目的/いつ使う

`<` と `<=` の取り違え、オフバイワン、上限下限の扱いを検出する。
同値分割とほぼ常にセットで使う。
順序を持たない離散的入力(列挙値の集合など)には境界が無いので不要。

### TypeScript example

0-100 のみ受理するスコア検証関数を、境界の代表値配列で回す。
2点境界(on/off)に加え、必要なら3点(直前も)を足す。

```ts
import { describe, it, expect } from "vitest";
import { isValidScore } from "./score";

describe("isValidScore: boundary values (range 0..100)", () => {
  const cases = [
    { value: -1, expected: false }, // 下限直前
    { value: 0, expected: true }, //   下限上
    { value: 1, expected: true }, //   下限直後
    { value: 99, expected: true }, //  上限直前
    { value: 100, expected: true }, // 上限上
    { value: 101, expected: false }, // 上限直後
  ] as const;

  it.each(cases)("score=$value -> $expected", ({ value, expected }) => {
    expect(isValidScore(value)).toBe(expected);
  });
});
```

### 落とし穴

- 浮動小数の境界は次の表現可能値が `±1` でない。`Number.EPSILON` 相当を意識する。
- 上限のみ、下限のみを検査して片側に偏る。両端を必ず出す。
- **境界を作る定数(バッファ容量・上限件数・タイムアウト等)をテスト側に別の値で書き写す**。テストが本番より大きい容量で回っていたために本番だけ溢れる欠陥を素通しした実例がある。境界定数は本番の定義を import/参照して共有し、テスト側にリテラルを再記入しない。共有できない事情があるなら、両者の一致を assert するテストを1本置く。

### 網羅の定義

- **網羅基準**：全境界について直前、境界上、直後を踏んだとき網羅完了。2点境界なら on/off の両端で足りる。
- **網羅手順**：
  1. 同値分割で得たクラス間の境界をすべて列挙する。
  2. 各境界に直前、境界上、直後の3点(または on/off の2点)を割り当て、1ケースずつにする。
- **達成チェック**：片側(上限だけ、下限だけ)になっている境界が無いか、両端の対称性を確認する。
- 浮動小数の境界では `±1` でなく次の表現可能値(`Number.EPSILON` 相当)を使えているか見る。

---

## ドメイン分析テスト(Domain Analysis)

### 概要

複数の入力変数が同時に効くとき、各変数の境界を on(境界上)/off(境界の外側直近)/in(領域の内側)/out(領域の外側)の点で攻める。
境界値分析を多変数へ拡張したもので、1つの変数の境界を1ケースで攻める間、他の変数は領域内(in)に固定する(1点1テスト原則)。

### 目的/いつ使う

判定が複数の入力変数の組合せで決まり、各変数に順序境界があるとき(矩形領域への内外判定、与信スコア×年収のしきい値、座標が範囲内か、など)に使う。
境界値分析を変数ごとに別々に回すと変数間の組合せを取りこぼすので、その隙間を埋めたいときに足す。
変数が1つだけなら境界値分析で足り、変数が独立な真偽の組合せならデシジョンテーブルへ進む。

### TypeScript example

矩形領域 `0<=x<=100, 0<=y<=50` に点が入るかの判定を、各境界の on/off と他変数 in 固定で回す。

```ts
import { describe, it, expect } from "vitest";
import { inRegion } from "./region";

describe("inRegion: domain analysis (0<=x<=100, 0<=y<=50)", () => {
  // 各行は1つの変数の境界を攻め、他変数は in(領域内)に固定する
  const cases = [
    { label: "x lower on",  x: 0,   y: 25, expected: true },  // x=境界上, y=in
    { label: "x lower off", x: -1,  y: 25, expected: false }, // x=境界外直近
    { label: "x upper on",  x: 100, y: 25, expected: true },
    { label: "x upper off", x: 101, y: 25, expected: false },
    { label: "y lower on",  x: 50,  y: 0,  expected: true },  // y=境界上, x=in
    { label: "y lower off", x: 50,  y: -1, expected: false },
    { label: "y upper on",  x: 50,  y: 50, expected: true },
    { label: "y upper off", x: 50,  y: 51, expected: false },
    { label: "interior in", x: 50,  y: 25, expected: true },  // in: 領域内部
    { label: "exterior out", x: 200, y: 200, expected: false }, // out: 両変数とも外
  ] as const;

  it.each(cases)("$label ($x,$y) -> $expected", ({ x, y, expected }) => {
    expect(inRegion(x, y)).toBe(expected);
  });
});
```

### 落とし穴

- 変数が独立でない(相関する境界、たとえば `x <= y` のような連動制約)とき、各変数を別々に攻めると非実現の組合せ(あり得ない点)を作ってしまう。制約を満たす範囲内で境界を選ぶ。
- on/off だけ並べて in/out を省くと、領域の内部・外部に潜む欠陥(境界以外の場所での誤判定)を逃す。各変数の境界点に加え、領域内 in と領域外 out の代表点を必ず1つずつ置く。
- ある変数の境界を攻めるときに他変数まで境界へ寄せると、どの変数の欠陥で落ちたか切り分けられない。攻める1変数以外は in に固定する。

### 網羅の定義

- **網羅基準**：各境界について on/off/in/out の4点(最低でも on/off の2点)を踏み、かつ領域全体に対する in 代表点と out 代表点を踏んだとき網羅完了。
- **網羅手順**：
  1. 判定に効く入力変数と、各変数の境界をすべて列挙する。
  2. 各境界に on(境界上)/off(外側直近)を割り当て、他変数は in(領域内)に固定して1ケースずつにする(1点1テスト原則)。
  3. 領域内部の in 代表点と、領域外の out 代表点を各1ケース足す。
  4. 変数間に相関制約があれば、それを満たす組合せだけ残す。
- **達成チェック**:on/off を攻める各ケースで、攻める変数以外がすべて in に固定されているか確認する。in/out の代表点が欠けていないか確認する。
- 変数が独立でないとき、非実現の組合せ(制約に反する点)を誤って採用していないか見る。

---

## デシジョンテーブル(Decision Table)

### 概要

複数の条件(原因)の真偽の組合せと、それぞれに対応するアクション(結果)を表に並べ、各列(ルール)を1テストケースにする。

### 目的/いつ使う

ビジネスルールが複数条件の AND/OR 組合せで分岐するときに使う(割引適用、与信判定、料金計算など)。
条件が1つだけのとき、または条件が独立で組合せ効果が無いときは過剰。

### TypeScript example

会員とクーポンで送料を決めるルールを、テーブルの各行として列挙する。

```ts
import { describe, it, expect } from "vitest";
import { shippingFee } from "./shipping";

describe("shippingFee: decision table", () => {
  // member | coupon | expected
  const rules = [
    { member: true, coupon: true, expected: 0 },
    { member: true, coupon: false, expected: 0 },
    { member: false, coupon: true, expected: 0 },
    { member: false, coupon: false, expected: 500 },
  ] as const;

  it.each(rules)(
    "member=$member coupon=$coupon -> fee=$expected",
    ({ member, coupon, expected }) => {
      expect(shippingFee({ member, coupon })).toBe(expected);
    },
  );
});
```

### 落とし穴

- 条件 n 個で組合せは 2ⁿ。意味のない組合せは実現不可(don't care)として畳み、全爆発を持ち込まない。
- 表に出ない組合せ(暗黙のデフォルト)を放置すると、そこに欠陥が隠れる。

### 網羅の定義

- **網羅基準**：実現可能な全ルール(条件の組合せ列)を各1ケース踏んだとき網羅完了。
- **網羅手順**：
  1. 分岐に効く条件をすべて抽出する。
  2. 条件 n 個の 2ⁿ 列を表に展開する。
  3. 結果が同一になる実現不可、無意味な列を don't care として畳む。
  4. 残った各列を1ケースにする。
- **達成チェック**：暗黙のデフォルト列が表に明示されているか確認する。
- 畳んだ列が本当に到達不能か(条件間の依存で消えるのか)を再確認する。

---

履歴と状態に依存する技法(状態遷移、CRUD / エンティティライフサイクル)は [`blackbox-state.md`](../blackbox-state/SKILL.md) を参照。
条件や因子の組合せを縮約する技法のうち論理ベース(原因結果グラフ、クラシフィケーションツリー)は [`blackbox-cause-effect.md`](../blackbox-cause-effect/SKILL.md) を、因子被覆(ペアワイズ、直交表、T-way)は [`blackbox-covering.md`](../blackbox-covering/SKILL.md) を参照。
