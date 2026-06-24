# テストダブル

本物の協力者の代わりに差し込む偽物(テストダブル)の種類と使い分けをまとめる。
出典は Gerard Meszaros の用語を Vladimir Khorikov が整理したもの。
TDD の手順は [`tdd-workflow.md`](tdd-workflow.md)、良いテストの規範(特にモック濫用の回避)は [`good-test-principles.md`](good-test-principles.md) を参照。

各項目は「概要」「目的/いつ使う」「TypeScript example(vitest 想定)」「落とし穴」の構成で示す。

## 目次

- [ダミー、スタブ、モック、スパイ、フェイク](#ダミースタブモックスパイフェイク)
- [Testcontainers](#testcontainers)

---

## ダミー、スタブ、モック、スパイ、フェイク

### 概要
テストダブルの五分類(Gerard Meszaros の用語を Khorikov が整理したもの)。
本物の協力者の代わりに差し込む偽物の総称がテストダブルである。

- **ダミー(Dummy)**：渡すだけで使われない値。`null` や空オブジェクトなど、引数を埋めるためだけのもの。
- **スタブ(Stub)**：テスト対象へ入力を供給する。あらかじめ用意した戻り値を返す。受信側であり、検証はしない。
- **モック(Mock)**：テスト対象から外部への呼び出し(出力)を検証する。送信側であり、呼び出されたことを確かめる。
- **スパイ(Spy)**：モックと同じ役割を手書きで実装したもの。呼び出しを記録して後で検証する。
- **フェイク(Fake)**：本物相当の軽量な実装。インメモリのリポジトリなど。

### 目的/いつ使う
スタブとモックは役割で截然と分ける。
**スタブは入力を供給する受信側で、決して検証しない**。
**モックは外部への出力を検証する送信側で、`toHaveBeenCalledWith` 等で呼び出しを確かめる**。
スタブに対して呼び出し検証を行うのは過剰検証(over-specification)であり、脆さの主因になる。
一つのダブルがスタブ(戻り値供給)とモック(呼び出し検証)を兼ねる設計は避ける。

### TypeScript example
```ts
import { describe, it, expect, vi } from "vitest";
import { PriceQuote } from "./price-quote";

it("stub supplies input, mock verifies output", () => {
  // スタブ: 入力を供給するだけ。戻り値を用意し、呼び出しは検証しない
  const rateApi = { rateOf: vi.fn().mockReturnValue(150) };

  // モック: 外部への通信を検証する送信側
  const auditLog = { record: vi.fn() };

  const quote = new PriceQuote(rateApi, auditLog);
  const result = quote.inUsd(300);

  // スタブが供給した値の結果は「状態/出力」で確かめる(スタブ自体は検証しない)
  expect(result).toBe(2); // 300 / 150
  // モックは呼び出しを検証する
  expect(auditLog.record).toHaveBeenCalledWith("quote", 2);
});
```

### 落とし穴
- スタブに `toHaveBeenCalled` を掛けて検証し、入力供給にすぎないものを過剰に固定する。
- フェイクの挙動が本物と乖離し、テストは緑でも本番で壊れる。フェイクは本物の契約を守る。

### 網羅設計での効かせ方
ダブルの選択は「何を網羅対象にし、何を差し替えるか」の線引きそのものである。
スタブは入力供給にすぎず網羅対象ではない。スタブ自体の呼び出しは検証しない。
モックは管理外のプロセス外依存への出力を網羅対象とし、呼び出しを検証する。
ゆえに「外部に出る副作用の組合せ」を網羅したいときはモックの検証点が網羅対象の集合を定める。
スタブに呼び出し検証を掛けると、入力供給まで網羅対象に紛れ込み、過剰検証で脆い網羅になる。
フェイク(インメモリ等)は管理下の依存を本物相当で網羅し、最終状態で検証する。
一つのダブルにスタブとモックを兼ねさせると、網羅対象(出力)と前提(入力)が混線して何を網羅したか不明になる。
よって網羅設計の最初の判断は、各協力者を「入力前提=スタブ/フェイク」と「網羅対象の出力=モック」へ振り分けることだ。

---

## Testcontainers

### 概要
データベースやメッセージブローカーなどの実ミドルウェアを、テスト実行のたびに使い捨てコンテナとして起動するライブラリ。

### 目的/いつ使う
管理下にあるプロセス外依存(自前 DB など)を、モックではなく本物で検証したいときに使う。
モック化はリポジトリ層の実装詳細へ結合するため、Khorikov は管理下の依存を本物でテストすることを勧める。
インメモリ偽物では SQL 方言やトランザクションの差で本番と乖離するが、Testcontainers は本番と同じエンジンを使うのでその乖離が出ない。
単体テストではなく結合テストの道具である点に注意する。

### TypeScript example
```ts
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { PostgreSqlContainer, StartedPostgreSqlContainer } from "@testcontainers/postgresql";
import { UserRepo } from "./user-repo";

let container: StartedPostgreSqlContainer;

beforeAll(async () => {
  container = await new PostgreSqlContainer("postgres:16").start();
}, 60_000);

afterAll(async () => {
  await container.stop();
});

it("persists and reads back a user (real Postgres)", async () => {
  const repo = await UserRepo.connect(container.getConnectionUri());
  await repo.save({ email: "a@example.com" });
  // 状態ベースで検証する。モックではないので実装詳細に結合しない
  expect(await repo.findByEmail("a@example.com")).toBeDefined();
});
```

### 落とし穴
- 速度が単体テストより桁違いに遅い。全テストを Testcontainers へ寄せず、結合テストの少数に絞る。
- コンテナの起動時間を見込まずタイムアウトで落ちる。起動に十分な制限時間を与える。

### 網羅設計での効かせ方
Testcontainers は、管理下のプロセス外依存(自前 DB など)を本物のエンジンで網羅するための道具である。
インメモリの偽物で代用すると、SQL 方言やトランザクション分離レベルの差で網羅に穴が残り、本番と乖離する。
ゆえにリポジトリ層の「クエリ、制約、トランザクション境界」を網羅したいなら、本物エンジン上で網羅対象を踏む。
網羅対象は永続化の最終状態であり、状態ベースで検証する。実装詳細(発行 SQL の文字列)を網羅対象にしない。
ただし起動が遅いため、すべての網羅をここへ寄せない。
入力の同値分割や境界値といった広い網羅は単体テストで取り、ここは結合の代表ケースに絞る。
配分の原則は、単体テストで論理の網羅を厚く取り、Testcontainers では「本物の依存と本当に繋がるか」の少数の網羅に限ることだ。
