---
name: oracle-model-based
description: >
  期待値を1つずつ手で用意できないとき、システムの振る舞いを抽象モデル(状態機械など)で表し、
  そこからテスト系列(操作の列)を自動生成して実システムと突き合わせるモデルベーステスト
  (Model-Based Testing)を扱う。test-catalog の手法カタログの一部。
  抽象モデルの定義、fast-check の commands によるステートフル PBT、
  状態・遷移の網羅確認、モデルの素朴さの維持を検証したい、または割り当てたいときに使う。
  通常は test-catalog スキルの索引経由で手法が選定された後にこのスキルを直接参照する。
disable-model-invocation: true
---

# モデルベーステスト(抽象モデルを oracle に据える)

oracle 問題への他の解(メタモルフィック、形式検証連携)は [`oracle-relational.md`](../oracle-relational/SKILL.md)、過去出力を基準にする系(ゴールデン、承認)は [`oracle-past-output.md`](../oracle-past-output/SKILL.md)、別実装との差分は [`oracle-differential.md`](../oracle-differential/SKILL.md)、ランダム入力で性質を確かめる系は [`generative-property.md`](../generative-property/SKILL.md) を参照。

## モデルベーステスト(Model-Based Testing)

### 概要
システムの振る舞いを抽象モデル(状態機械など)で表し、そこからテスト系列(操作の列)を自動生成して実システムと突き合わせる。

### 目的/いつ使う
操作の順序や履歴に依存する対象(プロトコル、ステートフルな API、UI フロー、データ構造)で、人手では思いつかない操作列を網羅したいときに使う。
モデル側を oracle として、各操作後にモデルと実装の状態が一致するかを判定する。
状態も順序も無い純粋関数には過剰。通常の PBT で足りる。

### TypeScript example
fast-check の `commands`(ステートフル PBT)で、抽象モデルと実装に同じ操作列を適用する。
LRU キャッシュ(容量2)を例に、各操作の `check`(事前条件)/`run`(モデルと実装を両方進めて照合)を埋める。

```ts
import { describe, it } from "vitest";
import fc from "fast-check";
import { newCache, type Cache } from "./lru-cache";

// 抽象モデル: 期待される振る舞いの最小実装(oracle)。実装より素朴に保つ
type Model = { entries: Map<number, number>; capacity: number };

// 操作: put(key, value)
class PutCommand implements fc.Command<Model, Cache> {
  constructor(readonly key: number, readonly value: number) {}
  check = () => true; // put はいつでも実行可
  run(m: Model, real: Cache): void {
    real.put(this.key, this.value);
    // モデル側を「素朴な LRU」として進める: 既存キーは削除して末尾へ入れ直す
    m.entries.delete(this.key);
    m.entries.set(this.key, this.value);
    if (m.entries.size > m.capacity) {
      const oldest = m.entries.keys().next().value; // 最古 = 先頭
      m.entries.delete(oldest);
    }
  }
  toString = () => `put(${this.key},${this.value})`;
}

// 操作: get(key) — モデルと実装の戻り値が一致するか各ステップで照合
class GetCommand implements fc.Command<Model, Cache> {
  constructor(readonly key: number) {}
  check = () => true;
  run(m: Model, real: Cache): void {
    const got = real.get(this.key);
    const expected = m.entries.get(this.key);
    if (got !== expected) throw new Error(`get(${this.key}): real=${got} model=${expected}`);
    // get もアクセス順を更新する LRU なら、モデル側も末尾へ移す
    if (m.entries.has(this.key)) {
      const v = m.entries.get(this.key)!;
      m.entries.delete(this.key);
      m.entries.set(this.key, v);
    }
  }
  toString = () => `get(${this.key})`;
}

describe("lru-cache: model-based", () => {
  it("matches the naive LRU model under any command sequence", () => {
    const commands = [
      fc.tuple(fc.integer({ min: 0, max: 3 }), fc.integer()).map(([k, v]) => new PutCommand(k, v)),
      fc.integer({ min: 0, max: 3 }).map((k) => new GetCommand(k)),
    ];
    fc.assert(
      fc.property(fc.commands(commands, { size: "large" }), (cmds) => {
        const setup = () => ({
          model: { entries: new Map<number, number>(), capacity: 2 },
          real: newCache(2),
        });
        fc.modelRun(setup, cmds); // 各 Command の check→run を順に適用し照合
      }),
    );
  });
});
```

### 落とし穴
- モデルが実装と同程度に複雑だと、モデル自身にバグが入りやすくなり、oracle を信頼できなくなる。モデルは意図的に素朴に保つ。
- 操作列が長くなると失敗の再現と最小化に時間がかかる。shrink で最小化できる範囲に操作を絞る。

### 遂行手順(着手→完了)
モデルベーステストは「**抽象モデルを定義 → そこから操作列を生成 → SUT にも同じ操作を適用し各ステップで照合 → 状態と遷移を網羅できたか確認**」の4工程からなる。次の順で進める。

1. **抽象モデルを定義する**:対象の状態を、実装より**意図的に素朴な**データ構造で表す(例: LRU を `Map` の挿入順で表す)。状態に対する各操作(put/get/delete…)が状態をどう変えるか、戻り値が何かを書く。**モデルが実装と同じ複雑さになったら設計を疑う**(モデルにバグがあると oracle を信頼できない)。状態遷移そのものの設計が非自明なら、先に [`loop-engineering`](../loop-engineering/SKILL.md)(TLA+)で状態機械を固めてからモデルに写す。
2. **操作と事前条件を列挙する**:各操作を `Command` にし、`check`(その状態で操作が許されるか=事前条件)と `run`(モデルと実装を両方進めて照合)を埋める。事前条件で禁止される列(空状態での pop 等)を `check` で除けば、無効列の生成を避けられる。
3. **操作列を生成してモデルと実装に適用する**:`fc.commands` で操作列を生成し、`fc.modelRun` でモデルと実装を1ステップずつ進める。**各操作後に**戻り値の一致(get の結果)と状態 invariant(サイズ上限、順序)を `run` 内で照合する。「最後だけ照合」では途中のずれを見逃す。
4. **状態・遷移網羅を確認する**:生成された操作列が、モデルの**到達可能な状態**と**各遷移**を通っているかを確かめる。`fc.commands` の `size` を上げる、操作の生成確率を調整する、足りない遷移(例: 容量超過での追い出し、ヒット/ミス両方)を通る操作を生成器に足す。状態機械を [`loop-engineering`](../loop-engineering/SKILL.md) で書いているなら、TLC が通った状態・遷移の集合を網羅の基準台帳に使う。
5. **反例を最小化して切り分ける**:照合が一致しなかったら shrink で最小操作列を得て、モデルのバグか実装のバグかを切り分ける。操作列が長すぎて shrink で最小化できないなら、操作の種類か値域を絞る。

### 完了チェック(もれ確認)
- **モデルが素朴に保たれているか**:モデルの行数・分岐が実装と同程度に増えていないか。増えていれば oracle 自体が信頼できない(モデルにバグがあると、合格も失敗も信用できない)。
- **状態網羅が取れているか**:モデルの到達可能な状態(空、1件、容量ちょうど、容量超過など)を操作列が全て通ったか。`fc.statistics` 等で生成列の分布を出し、特定状態に偏っていないか確認する。通っていない状態があれば生成器を調整する。
- **遷移網羅が取れているか**:各操作 × 状態の組(例: 満杯時の put、ミス時の get)を通ったか。通らなかった遷移は人手で1ケース足す。TLA+ で状態機械を書いているなら TLC の遷移集合と突き合わせる。
- **各ステップで照合しているか**:`run` 内で戻り値と invariant を毎操作チェックしているか(最後だけの照合になっていないか)。
- **複数回通るか**:seed を変えて複数回実行しても失敗しないか。失敗する列が出たら shrink で最小反例を確保する([`../test-verify/SKILL.md`](../test-verify/SKILL.md) の実行ゲート)。

### 網羅の定義
- **網羅基準**:モデル(状態機械)から生成した操作列で、到達したモデル状態と遷移を網羅し、各操作後にモデルと実装が一致する。
- **網羅手順**:
  1. 抽象モデルを定義する。
  2. `fast-check` の commands 等で操作列を生成する。
  3. 各操作後に invariant を照合する。
- **達成チェック**:モデルが素朴に保たれ oracle を信頼できるか確認する。操作列が長すぎず、shrink で最小化できる長さに収まっているかを見る。
