# ブラックボックス設計技法（入力空間の分割と履歴）

内部実装を見ず、入出力仕様だけからテストケースを機械的に導く体系的技法群。
ISO/IEC/IEEE 29119-4 はこれらを「仕様ベースのテスト設計技法(specification-based techniques)」として体系化している。
コードを開かずに何を確かめるべきかを決められるので、実装前(TDD のテストリスト)にも有効。

ここでは入力空間の分割と履歴を扱う技法(同値分割、境界値分析、デシジョンテーブル、状態遷移)をまとめる。
条件や因子の組合せが爆発するときにそれを縮約する技法(原因結果グラフ、ペアワイズ、クラシフィケーションツリー)は [`blackbox-combinatorial.md`](blackbox-combinatorial.md) を参照。
経験と直感に依る非形式的な技法(ユースケース、シナリオ、エラー推測、探索的、アドホック)は [`blackbox-experience.md`](blackbox-experience.md) を参照。

各手法は独立ではなく重ねて使う。
まず同値分割で入力空間を割り、境界値で割れ目を攻め、条件の組合せはデシジョンテーブル、振る舞いの履歴依存は状態遷移、という順で必要なものだけ足す。

## 目次

- [同値分割(Equivalence Partitioning)](#同値分割equivalence-partitioning)
- [境界値分析(Boundary Value Analysis)](#境界値分析boundary-value-analysis)
- [ドメイン分析テスト(Domain Analysis)](#ドメイン分析テストdomain-analysis)
- [デシジョンテーブル(Decision Table)](#デシジョンテーブルdecision-table)
- [状態遷移テスト(State Transition)](#状態遷移テストstate-transition)
- [CRUD / エンティティライフサイクルテスト(CRUD / Entity Lifecycle)](#crud--エンティティライフサイクルテストcrud--entity-lifecycle)

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

## 状態遷移テスト(State Transition)

### 概要

対象を状態と遷移(イベント → 次状態)のモデルとして捉え、各遷移、無効遷移、状態の往復をテストする。

### 目的/いつ使う

振る舞いが過去の履歴に依存するときに使う(注文ステータス、認証セッション、UI のモード)。
正当な遷移だけでなく、その状態で来てはいけないイベントも検査するのが肝。
入力から出力が一意に決まる純関数には状態が無いので不要。
状態空間が広く全 interleaving や到達性を厳密に押さえたい設計は、テストでなく `loop-engineering`(TLA+)でモデル検査してから、反例をここへ落とす。

### TypeScript example

注文ステートマシンの遷移表をそのままテーブルにする。
無効遷移は現状維持(または例外)を確認する。

```ts
import { describe, it, expect } from "vitest";
import { next } from "./order";

describe("order state machine: transitions", () => {
  const valid = [
    { from: "created", event: "pay", to: "paid" },
    { from: "paid", event: "ship", to: "shipped" },
    { from: "shipped", event: "deliver", to: "delivered" },
  ] as const;

  it.each(valid)("$from --$event--> $to", ({ from, event, to }) => {
    expect(next(from, event)).toBe(to);
  });

  it("rejects invalid transition (created --ship-->)", () => {
    expect(() => next("created", "ship")).toThrow();
  });
});
```

### 落とし穴

- 有効遷移だけ書いて、無効イベント(状態 × 起こり得ないイベント)を全く検査しない。欠陥はそこに住む。
- 状態爆発を招く。まず 0-switch(各遷移1回)で足り、必要な箇所だけ N-switch(連鎖)へ上げる。

### 網羅の定義

- **網羅基準(段階的)**：まず 0-switch で全有効遷移と各状態の全無効イベントを踏む。必要な箇所だけ N-switch(遷移連鎖)へ上げる。
- **網羅手順**：
  1. 状態遷移表(状態 × イベント → 次状態)を作る。
  2. 表から有効遷移をすべて列挙する。
  3. 各状態について起こりうる全イベントを当て、有効でない分を無効遷移として列挙する。
- **達成チェック**：無効遷移(状態 × 来てはいけないイベント)が一つも欠けていないか確認する。
- 状態爆発する設計は、ここで全 interleaving を網羅しようとせず `loop-engineering`(TLA+)へ委ね、反例を遷移ケースとして落とす。

### 禁止仕様からのテスト導出(許可される列・禁止される列)

無効遷移は、ある状態で来てはいけない1イベントを見る。
これを**列**へ一般化すると、N-switch のケースを思いつきでなく機械的に作れる。
観点は2つある。

- **禁止される列(拒否)**：本来到達不能なイベント列。最後まで流すと途中で止まる、例外になる、状態が進まないことを確認する。たとえば `(注文作成 → 出荷)` は支払いを飛ばしているので拒否されねばならない。無効遷移の単発版を、そこへ至る列へ伸ばしたものにあたる。
- **許可される列(受理)**：本来到達できる正常列。最後まで流せて、各ステップで期待した次イベントが受理可能であることを確認する。たとえば `(作成 → 支払い → 出荷 → 配達)` が全段通る。

導出の起点は、来てはいけない振る舞いのリストである。
機能要求を禁止される列の集合として書き出すと、各禁止列が1本の拒否テストに、その境界にある正常列が受理テストに、ほぼ1対1で落ちる(`good-test-principles.md` の振る舞いからテストへの橋渡しと同じ向き)。

```ts
describe("order state machine: traces", () => {
  const run = (events: string[]) => events.reduce((s, e) => next(s, e), "created");

  // 許可される列(受理): 最後まで流せる
  it("accepts (pay, ship, deliver)", () => {
    expect(run(["pay", "ship", "deliver"])).toBe("delivered");
  });

  // 禁止される列(拒否): 途中で止まる
  it("rejects (ship ...) — payment skipped", () => {
    expect(() => run(["ship", "deliver"])).toThrow();
  });
});
```

落とし穴は、禁止列を異常系の入力1個と同一視して単発に縮めてしまうことである。
履歴の途中まで正常で、ある一手で初めて禁止になる列(連休跨ぎ、二重支払い、期限切れ後の操作)が N-switch の本命で、ここが単発検査からこぼれる。
状態空間が広く禁止列の網羅性を厳密に押さえたいなら、列の生成は `loop-engineering`(TLA+)に任せ、反例トレースをそのまま拒否テストへ落とす。

---

## CRUD / エンティティライフサイクルテスト(CRUD / Entity Lifecycle)

### 概要

エンティティの一生(create → read → update → delete)を一貫したシナリオとして辿り、各操作の結果が次の操作に正しく反映されることを検査する。
扱うエンティティと操作 {C,R,U,D} のマトリクスを作り、各セルが少なくとも1ケースで埋まることを網羅基準にする。

### 目的/いつ使う

永続化を伴うリソース(DB レコード、API リソース、ファイル)を CRUD する層に使う(リポジトリ、永続化層、REST リソース)。
個々の操作を孤立して検査するだけだと、作成直後の読み出し、更新後の再読み出し、削除後の参照といった**操作間の整合**が抜ける。ライフサイクル全体を1本で辿ってそこを埋める。
状態が分岐し履歴依存が複雑なものは、CRUD ではなく状態遷移テスト(上)へ進む。CRUD は線形なライフサイクルの完全性を見るのに向く。

### TypeScript example

ユーザーリポジトリの C→R→U→R→D→R を1本のシナリオで辿る。削除後の読み出しが不在(null)になることを必須で確認する。

```ts
import { describe, it, expect, beforeEach } from "vitest";
import { UserRepo } from "./userRepo";

describe("UserRepo: CRUD lifecycle", () => {
  let repo: UserRepo;
  beforeEach(() => {
    repo = new UserRepo();
  });

  it("create -> read -> update -> read -> delete -> read", async () => {
    // C: 作成し、生成 id が返る
    const id = await repo.create({ name: "alice" });
    expect(id).toBeTruthy();

    // R: 作成直後に読めて、書いた値が反映されている
    expect(await repo.read(id)).toMatchObject({ name: "alice" });

    // U: 更新が次の read に反映される
    await repo.update(id, { name: "bob" });
    expect(await repo.read(id)).toMatchObject({ name: "bob" });

    // D: 削除後の read は不在(null)になる(削除後参照の必須確認)
    await repo.delete(id);
    expect(await repo.read(id)).toBeNull();
  });

  it("update is idempotent for same payload", async () => {
    const id = await repo.create({ name: "alice" });
    await repo.update(id, { name: "bob" });
    await repo.update(id, { name: "bob" });
    expect(await repo.read(id)).toMatchObject({ name: "bob" });
  });
});
```

### 落とし穴

- read のテストだけ厚くして、delete 後の参照(404 / null / 論理削除フラグ)を検査しない。削除済みエンティティへのアクセスは欠陥の温床なので必須にする。
- update の冪等性(同じ更新を2回当てても結果が同じ)と部分更新(一部フィールドだけ更新し他は保持)を見落とす。
- create の重複(同一キーの二重作成)や、存在しない id への update/delete の振る舞いを検査しない。これらは異常系として別ケースに立てる。

### 網羅の定義

- **網羅基準**：全エンティティ × {C,R,U,D} のマトリクスが各1ケース以上で埋まり、かつ削除後の R(不在確認)が踏まれたとき網羅完了。
- **網羅手順**：
  1. 対象エンティティをすべて列挙し、行に並べる。
  2. 列に {C,R,U,D} を置き、エンティティ × 操作のマトリクスを作る。
  3. 各エンティティについて C→R→U→R→D→R を辿る基本シナリオを1本立て、全セルを埋める。
  4. 削除後の R(不在確認)、存在しない id への U/D、重複 C、部分更新と冪等性を異常系・性質のケースとして足す。
- **達成チェック**:マトリクスに空セル(検査されていないエンティティ×操作)が無いか確認する。削除後の R が各エンティティで踏まれているか確認する。
- 状態分岐が複雑で線形ライフサイクルに収まらないものは、CRUD ではなく状態遷移テストへ移したか見る。

---

条件や因子の組合せを縮約する技法(原因結果グラフ、ペアワイズ、クラシフィケーションツリー)は [`blackbox-combinatorial.md`](blackbox-combinatorial.md) を参照。
