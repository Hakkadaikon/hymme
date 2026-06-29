# ブラックボックス設計技法(履歴と状態)

内部実装を見ず、入出力仕様だけからテストケースを機械的に導く体系的技法群。
ISO/IEC/IEEE 29119-4 はこれらを「仕様ベースのテスト設計技法(specification-based techniques)」として体系化している。
コードを開かずに何を確かめるべきかを決められるので、実装前(TDD のテストリスト)にも有効。

ここでは振る舞いが過去の履歴に依存する技法(状態遷移、CRUD / エンティティライフサイクル)をまとめる。
入力空間の分割を扱う技法(同値分割、境界値分析、ドメイン分析、デシジョンテーブル)は [`blackbox-partition.md`](blackbox-partition.md) を参照。
条件や因子の組合せが爆発するときにそれを縮約する技法のうち論理ベース(原因結果グラフ、クラシフィケーションツリー)は [`blackbox-cause-effect.md`](blackbox-cause-effect.md) を、因子被覆(ペアワイズ、直交表、T-way)は [`blackbox-covering.md`](blackbox-covering.md) を参照。
経験と直感に依る非形式的な技法のうち、業務フロー起点(ユースケース、シナリオ、構文テスト)は [`experience-scenario.md`](experience-scenario.md) を、経験・乱数起点(エラー推測、ランダムファジング、探索的、アドホック)は [`experience-heuristic.md`](experience-heuristic.md) を参照。

各手法は独立ではなく重ねて使う。
まず同値分割で入力空間を割り、境界値で割れ目を攻め、条件の組合せはデシジョンテーブル、振る舞いの履歴依存は状態遷移、という順で必要なものだけ足す。

## 目次

- [状態遷移テスト(State Transition)](#状態遷移テストstate-transition)
- [CRUD / エンティティライフサイクルテスト(CRUD / Entity Lifecycle)](#crud--エンティティライフサイクルテストcrud--entity-lifecycle)

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

入力空間の分割(同値分割、境界値分析、ドメイン分析、デシジョンテーブル)は [`blackbox-partition.md`](blackbox-partition.md) を参照。
条件や因子の組合せを縮約する技法のうち論理ベース(原因結果グラフ、クラシフィケーションツリー)は [`blackbox-cause-effect.md`](blackbox-cause-effect.md) を、因子被覆(ペアワイズ、直交表、T-way)は [`blackbox-covering.md`](blackbox-covering.md) を参照。
