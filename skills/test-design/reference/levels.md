# テストレベル

対象の粒度によるテストの分類。
下に行くほど対象が広く、実行が遅く、本物の環境に近い。
ISO/IEC/IEEE 29119 が用語の基準だが、現場では下記の俗称が混在するため、各手法で「何を本物にし、何を差し替えるか」を明確にして選ぶ。

## 目次

- [単体テスト(Unit Test)](#単体テストunit-test)
- [結合テスト(Integration Test)](#結合テストintegration-test)
- [コンポーネントテスト](#コンポーネントテスト)
- [コントラクトテスト(Consumer-Driven Contract / Pact)](#コントラクトテストconsumer-driven-contract--pact)
- [システム全体のレベルは別ファイルへ](#システム全体のレベルは別ファイルへ)
- [配分と階層化は別ファイルへ](#配分と階層化は別ファイルへ)

## 単体テスト(Unit Test)

### 概要
関数、メソッド、クラスといった最小単位を、依存を切り離して検証する。

### 目的/いつ使う
ロジックの分岐、境界、例外を高速かつ大量に回したいときに使う。
外部 I/O やフレームワークの挙動そのものを確かめたい局面では使わない(それは結合より上の責務)。

### TypeScript example
```ts
import { describe, it, expect } from "vitest";

// 検証対象: 純粋関数。依存なしなのでそのまま呼べる
function applyDiscount(price: number, rate: number): number {
  if (rate < 0 || rate > 1) throw new RangeError("rate out of range");
  return Math.round(price * (1 - rate));
}

describe("applyDiscount", () => {
  it("割引を適用して四捨五入する", () => {
    expect(applyDiscount(1000, 0.1)).toBe(900);
  });
  it("境界: rate=1 は 0 円", () => {
    expect(applyDiscount(1000, 1)).toBe(0);
  });
  it("異常系: 範囲外の rate は例外", () => {
    expect(() => applyDiscount(1000, 1.5)).toThrow(RangeError);
  });
});
```

### 落とし穴
モックを積み上げて実装の呼び出し順をなぞるテストは、リファクタで即壊れる割に欠陥を捕まえない。
private メソッドを直接叩こうとするのは設計のにおい。公開された振る舞いで検証する。

### 網羅の定義

このレベルは「対象単位そのもののロジック網羅」を集約する層。
分岐、境界、例外の網羅はここで取り切り、上の層へ持ち上げない。

- **網羅基準(いつ網羅完了とみなすか)**：対象のブラックボックス技法(同値分割の全クラス各1代表 + 境界値 + 必要ならデシジョンテーブルの全規則)を満たし、かつホワイトボックスで C1(全分岐)を踏み、安全性に関わる複合条件は MC-DC を満たしたとき。
- **網羅手順(基準を満たすケース集合の作り方)**：1. 対象の入出力から有効/無効の同値クラスと境界を列挙する。2. 各クラスと境界に代表ケースを割り当てる。3. coverage 計測で未踏の分岐を洗い出し、それを踏むケースを追加する。
- **達成チェック(漏れの検出)**：外部 I/O や接続の検証がこの層に紛れていないか(それは結合へ委ねる)。逆にロジック分岐が上層へ漏れていないか(分岐網羅は単体に寄っているのが健全)。coverage の分岐到達率で未踏を検出する。

## 結合テスト(Integration Test)

### 概要
複数のモジュールや、コードと実依存(DB、キュー、別サービス)の境界をまたいで検証する。

### 目的/いつ使う
単体では見えない接続部のずれ(SQL の方言、シリアライズ、トランザクション境界)を捕まえたいときに使う。
ロジックの全分岐を網羅する用途には向かない(遅く、組み合わせ爆発する)。

### TypeScript example
```ts
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import Database from "better-sqlite3";
import { UserRepo } from "./user-repo";

let db: Database.Database;
let repo: UserRepo;

beforeAll(() => {
  // 本物の DB エンジンを使う。スキーマのずれをここで検出する
  db = new Database(":memory:");
  db.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)");
  repo = new UserRepo(db);
});
afterAll(() => db.close());

describe("UserRepo", () => {
  it("保存した行を取得できる", () => {
    const id = repo.insert("alice");
    expect(repo.findById(id)?.name).toBe("alice");
  });
});
```

### 落とし穴
共有 DB を使い回してテスト間で状態が漏れると、実行順で結果が変わる不安定なテストになる。
in-memory で代用すると本番 DB との方言差を見逃すことがある。重要な経路は本物のエンジンで確認する。

### 網羅の定義

このレベルは「モジュール境界と実依存との接続のずれ」を網羅対象に取る層。
全ロジック分岐は対象にしない(それは単体)。接続経路を代表で踏むことに集中する。

- **網羅基準(いつ網羅完了とみなすか)**：主要な接続経路(各実依存への読み/書き、トランザクション境界、シリアライズの往復)を代表ケースで一通り踏んだとき。分岐の全網羅は基準に含めない。
- **網羅手順(基準を満たすケース集合の作り方)**：1. 対象がまたぐ境界(DB、キュー、別サービス)を列挙する。2. 各境界で起こりうるずれ(SQL方言、型変換、コミット/ロールバック)を1観点ずつ代表ケースにする。3. 接続の成功経路と代表的な失敗経路を各1本ずつ用意する。
- **達成チェック(漏れの検出)**：共有状態(使い回す DB 等)でテスト間が汚染され実行順依存になっていないか。in-memory 代用で本物エンジンの方言差を踏み損ねていないか。重要経路は本物のエンジンで確認しているか。

## コンポーネントテスト

### 概要
1 つのサービスやモジュール群を 1 単位として、外部依存だけスタブ化して内部は本物のまま検証する。

### 目的/いつ使う
あるサービスを独立にデプロイ可能な箱とみなし、その箱単体の振る舞いを契約として固めたいときに使う。
複数サービスの連携全体を見たい局面では使わない(それはシステムテスト)。

### TypeScript example
```ts
import { describe, it, expect, vi } from "vitest";
import { OrderService } from "./order-service";

describe("OrderService(コンポーネント)", () => {
  it("在庫があれば注文を確定する", async () => {
    // 外部の決済 API だけスタブ。サービス内部のロジックは本物
    const payment = { charge: vi.fn().mockResolvedValue({ ok: true }) };
    const svc = new OrderService(payment);
    const result = await svc.placeOrder({ sku: "A1", qty: 2 });
    expect(result.status).toBe("confirmed");
    expect(payment.charge).toHaveBeenCalledOnce();
  });
});
```

### 落とし穴
スタブの返す形が実物の API とずれると、緑のまま本番で壊れる。
ここをコントラクトテストで裏打ちしないと、コンポーネント単体の安心は錯覚になる。

### 網羅の定義

このレベルは「1 サービスを箱とみなした外部契約としての振る舞い」を網羅対象に取る層。
外部依存はスタブ化し、内部は本物のままサービスの契約を踏む。

- **網羅基準(いつ網羅完了とみなすか)**：サービスが外部へ公開する振る舞い(主要なユースケースとその代表的な失敗)を、内部を本物にした状態で一通り踏んだとき。内部実装の分岐網羅は基準に含めない(単体の責務)。
- **網羅手順(基準を満たすケース集合の作り方)**：1. サービスの公開操作(エンドポイント/コマンド)を列挙する。2. 各操作の正常系と業務上意味のある失敗系を代表ケースにする。3. 外部依存をスタブ化し、内部ロジックは本物のまま結線して検証する。
- **達成チェック(漏れの検出)**：スタブの返す形が実 API とずれていないか。そのずれをコントラクトテストで裏打ちしているか(裏打ちが無いと緑のまま本番で壊れる)。

## コントラクトテスト(Consumer-Driven Contract / Pact)

### 概要
サービス間の API 契約(リクエスト/レスポンスの形)を、消費側が定義し提供側が満たすことを両端で検証する。

### 目的/いつ使う
マイクロサービスやチーム分割で、相手を立ち上げずに連携の互換性を担保したいときに使う。
単一プロセス内の呼び出しや、めったに変わらない安定 API には過剰。

### TypeScript example
```ts
import { PactV3, MatchersV3 } from "@pact-foundation/pact";
import { describe, it, expect } from "vitest";
import path from "node:path";
import { fetchUser } from "./user-client";

const { like } = MatchersV3;

describe("user-client の契約", () => {
  it("GET /users/:id がユーザーを返す", async () => {
    const provider = new PactV3({
      consumer: "web",
      provider: "user-api",
      dir: path.resolve(process.cwd(), "pacts"),
    });
    // 消費側が期待する形を宣言。提供側はこの pact ファイルで検証する
    provider
      .uponReceiving("a request for user 1")
      .withRequest({ method: "GET", path: "/users/1" })
      .willRespondWith({
        status: 200,
        body: { id: like(1), name: like("alice") },
      });

    await provider.executeTest(async (mock) => {
      const user = await fetchUser(mock.url, 1);
      expect(user.name).toBe("alice");
    });
  });
});
```

### 落とし穴
生成した pact を提供側の CI で検証しないと、契約はただのモック設定に堕ちる。
`like` で型だけ緩く合わせると、必須フィールドの欠落を見逃す。重要な値は具体例で固定する。

### 網羅の定義

このレベルは「サービス間 API の契約」を網羅対象に取る層。
消費側が実際に必要とするリクエスト/レスポンスの形を、両端で踏む。

- **網羅基準(いつ網羅完了とみなすか)**：消費側が利用する全エンドポイント × 期待するレスポンス形(必須フィールドを含む)を pact 化し、それを提供側 CI が検証して緑になったとき。
- **網羅手順(基準を満たすケース集合の作り方)**：1. 消費側コードが呼ぶエンドポイントを全て洗い出す。2. 各エンドポイントで消費側が依存する必須フィールドと値を具体例で固定する。3. 生成した pact を提供側の CI に渡して検証ジョブに組み込む。
- **達成チェック(漏れの検出)**：提供側で pact 検証が実際に回っているか(回らなければただのモック設定)。`like` で緩めすぎて必須フィールドの欠落を見逃していないか。消費側に未カバーの呼び出しが残っていないか。

## システム全体のレベルは別ファイルへ

システム全体を外から見るレベル(システムテスト、E2E テスト、受け入れテスト、スモークテスト、サニティテスト、回帰テスト)は、[levels-system.md](levels-system.md) にまとめた。
複数のサービスや UI、DB、設定が組み合わさった状態を扱うレベルは、そちらを読む。

## 配分と階層化は別ファイルへ

どのレベルに何本置くか(配分論)と、粒度とは別軸の階層化(関心事による分割)は、[`test-strategy.md`](test-strategy.md) にまとめた。
レベルを選んだあとのテスト戦略は、そちらを読む。
