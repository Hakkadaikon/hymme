# モデルベーステスト(抽象モデルを oracle に据える)

システムの振る舞いを抽象モデル(状態機械など)で表し、そこからテスト系列(操作の列)を自動生成して実システムと突き合わせる手法を扱う。
モデル側を oracle として、各操作後にモデルと実装の状態が一致するかを判定する。

oracle 問題への他の解(メタモルフィック、形式検証連携)は [`oracle-relational.md`](oracle-relational.md)、過去出力・別実装を基準にする系(ゴールデン、承認、差分)は [`oracle-snapshot.md`](oracle-snapshot.md)、ランダム入力で性質を叩く系は [`generative-property.md`](generative-property.md) を参照。

## モデルベーステスト(Model-Based Testing)

### 概要
システムの振る舞いを抽象モデル(状態機械など)で表し、そこからテスト系列(操作の列)を自動生成して実システムと突き合わせる。

### 目的/いつ使う
操作の順序や履歴に依存する対象(プロトコル、ステートフルな API、UI フロー、データ構造)で、人手では思いつかない操作列を網羅したいときに使う。
モデル側を oracle として、各操作後にモデルと実装の状態が一致するかを判定する。
状態も順序も無い純粋関数には過剰。通常の PBT で足りる。

### TypeScript example
fast-check の `commands`(ステートフル PBT)で、抽象モデルと実装を操作列で並走させる。
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
- モデルが実装と同程度に複雑だと、モデル自身がバグの温床になり oracle の信頼が崩れる。モデルは意図的に素朴に保つ。
- 操作列が長くなると失敗の再現と最小化が重い。shrink が効く範囲に操作を絞る。

### 遂行手順(着手→完了)
モデルベーステストの本体は「**抽象モデルを定義 → そこから操作列を生成 → SUT と並走させ各ステップで照合 → 状態と遷移を網羅できたか確認**」の4工程だ。次の順で進める。

1. **抽象モデルを定義する**:対象の状態を、実装より**意図的に素朴な**データ構造で表す(例: LRU を `Map` の挿入順で表す)。状態に対する各操作(put/get/delete…)が状態をどう変えるか、戻り値が何かを書く。**モデルが実装と同じ複雑さになったら設計を疑う**(モデルがバグると oracle が崩れる)。状態遷移そのものの設計が非自明なら、先に [`loop-engineering`](../../loop-engineering/SKILL.md)(TLA+)で状態機械を固めてからモデルに写す。
2. **操作と事前条件を列挙する**:各操作を `Command` にし、`check`(その状態で操作が許されるか=事前条件)と `run`(モデルと実装を両方進めて照合)を埋める。事前条件で禁止される列(空状態での pop 等)を `check` で除けば、無効列の生成を避けられる。
3. **操作列を生成して並走させる**:`fc.commands` で操作列を生成し、`fc.modelRun` でモデルと実装を1ステップずつ並走させる。**各操作後に**戻り値の一致(get の結果)と状態 invariant(サイズ上限、順序)を `run` 内で照合する。「最後だけ照合」では途中のずれを見逃す。
4. **状態・遷移網羅を確認する**:生成された操作列が、モデルの**到達可能な状態**と**各遷移**を踏んでいるかを確かめる。`fc.commands` の `size` を上げる、操作の生成確率を調整する、足りない遷移(例: 容量超過での追い出し、ヒット/ミス両方)を踏む操作を生成器に足す。状態機械を [`loop-engineering`](../../loop-engineering/SKILL.md) で書いているなら、TLC が踏んだ状態・遷移の集合を網羅の基準台帳に使う。
5. **反例を最小化して切り分ける**:照合が破れたら shrink で最小操作列を得て、モデルのバグか実装のバグかを切り分ける。操作列が長すぎて shrink が効かないなら、操作の種類か値域を絞る。

### 完了チェック(もれ確認)
- **モデルが素朴に保たれているか**:モデルの行数・分岐が実装と同程度に膨らんでいないか。膨らんでいれば oracle 自体が信頼できない(モデルがバグると緑も赤も信じられない)。
- **状態網羅が取れているか**:モデルの到達可能な状態(空、1件、容量ちょうど、容量超過など)を操作列が全て踏んだか。`fc.statistics` 等で生成列の分布を出し、特定状態に偏っていないか確認する。踏んでいない状態があれば生成器を調整する。
- **遷移網羅が取れているか**:各操作 × 状態の組(例: 満杯時の put、ミス時の get)を踏んだか。踏み損ねた遷移は人手で1ケース足す。TLA+ で状態機械を書いているなら TLC の遷移集合と突き合わせる。
- **各ステップで照合しているか**:`run` 内で戻り値と invariant を毎操作チェックしているか(最後だけの照合になっていないか)。
- **複数回緑か**:seed を変えて複数回回しても落ちないか。落ちる列が出たら shrink で最小反例を確保する([`../SKILL.md`](../SKILL.md) の実行ゲート)。

### 網羅の定義
- **網羅基準**:モデル(状態機械)から生成した操作列で、到達したモデル状態と遷移を網羅し、各操作後にモデルと実装が一致する。
- **網羅手順**:
  1. 抽象モデルを定義する。
  2. `fast-check` の commands 等で操作列を生成する。
  3. 各操作後に invariant を照合する。
- **達成チェック**:モデルが素朴に保たれ oracle の信頼が崩れていないか確認する。操作列が長すぎて shrink が効かなくないかを見る。

---

oracle 問題への他の解(メタモルフィック、形式検証連携)は [`oracle-relational.md`](oracle-relational.md) を参照。
