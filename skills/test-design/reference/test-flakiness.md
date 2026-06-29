# テストの flaky(不安定さ)の体系的対策

同じコードに対して同じテストが、走らせるたびに緑になったり赤になったりする状態を flaky と呼ぶ。
flaky テストは「赤を信用できない」状態を生み、本物の退行をノイズに埋もれさせ、緑を retry で握り潰す悪習を招く。
原因はほぼ常に**テストが制御していない非決定性**にある。時刻、乱数、並行、実行順序、外部ネットワーク、実時間待ち、浮動小数がその主な出どころだ。

ここでは flaky の主要因を一つずつ取り上げ、**各要因について「検出法(あぶり出す)」と「封じ込め(根治する)」を必ず対で**示す。
flaky は「たまたま緑」で見逃されるので、検出は意図的に揺らぎを増幅して再現させる。封じ込めは揺らぎの源をテストの制御下に引き込む(注入する、固定する、待ち合わせる)。

相互参照:

- 後始末漏れによるテスト間の状態汚染の構成パターンは [`test-structure.md`](test-structure.md) の Four-Phase Test(teardown)を参照。
- 外部依存をテストダブルへ置き換える使い分けは [`test-doubles.md`](test-doubles.md) を参照。
- 並行・状態遷移・順序の設計そのものをテスト前に固めるなら `loop-engineering`(TLA+)でモデル検査し、反例を回帰テストへ落とす。
- 性質ベースやメタモルフィックなテストの seed を変えた複数回実行は [`good-test-principles.md`](good-test-principles.md) / [`test-design-quality.md`](test-design-quality.md) の脆さの議論と接続する。

## 目次

- [時刻依存(now / Date)](#時刻依存now--date)
- [乱数・UUID](#乱数uuid)
- [並行・競合](#並行競合)
- [テスト間順序・状態漏れ](#テスト間順序状態漏れ)
- [外部ネットワーク](#外部ネットワーク)
- [タイマー・sleep](#タイマーsleep)
- [浮動小数](#浮動小数)
- [共通方針(隔離・検出の総論)](#共通方針隔離検出の総論)

---

## 時刻依存(now / Date)

### 原因

コードが `Date.now()` や `new Date()` を内部で直接呼ぶと、出力が実行時刻に依存する。
「今日の日付」「24時間以内か」「タイムゾーンを跨ぐ深夜」などは、実行する時刻・曜日・タイムゾーンで結果が変わり、特定の時間帯やうるう日・月末でだけ落ちる。

### 検出法

時刻を機械的に進めて反復する。`vi.setSystemTime` で深夜直前、月末、うるう日、年跨ぎ、各タイムゾーンの境界へ時計を置いてテストを回す。
固定時刻でなく「現在時刻」に依存しているテストは、CI が動く時間帯次第で落ちるので、ローカルでも時計をずらして再現させる。

### 封じ込め

時刻をテストの制御下に置く。根治は**時計の注入**——`now: () => Date` のような時刻源を引数やコンストラクタで受け取り、本番は `Date.now`、テストは固定値を渡す。
コードに手を入れにくいときは `vi.useFakeTimers()` + `vi.setSystemTime()` でグローバルな時計を固定する。いずれも、テストが時刻を**決める**状態にする。

### TypeScript example

悪い例(内部で現在時刻を読むので、実行時刻で結果が揺れる):

```ts
// expiry.ts
export function isExpired(token: { expiresAt: number }): boolean {
  return token.expiresAt < Date.now(); // テストから制御できない
}
```

直した例(時計を注入し、テストが時刻を固定する):

```ts
// expiry.ts
export function isExpired(token: { expiresAt: number }, now = () => Date.now()): boolean {
  return token.expiresAt < now();
}

// expiry.test.ts
import { describe, it, expect } from "vitest";
import { isExpired } from "./expiry";

describe("isExpired: 時刻を固定して境界を踏む", () => {
  const fixed = Date.parse("2026-06-29T00:00:00Z");
  const now = () => fixed;

  it("期限が現在より前なら期限切れ", () => {
    expect(isExpired({ expiresAt: fixed - 1 }, now)).toBe(true);
  });
  it("期限が現在ちょうどなら期限切れでない", () => {
    expect(isExpired({ expiresAt: fixed }, now)).toBe(false);
  });
});
```

---

## 乱数・UUID

### 原因

`Math.random()` や `crypto.randomUUID()` をコード内で直接呼ぶと、生成値が毎回変わる。
たまたま衝突しない値で緑になり、ある実行でだけ衝突・並び順違い・特定値で落ちる。アサーションが生成値そのものに依存していると、再現すらできない。

### 検出法

seed を変えて反復する。乱数源を差し替えられるなら複数の seed で同じテストを多数回回し、特定の seed でだけ落ちる組合せをあぶり出す。
property-based test では失敗時に seed と最小反例が出るので、それを回帰として固定する([`modern-generative.md`](modern-generative.md))。

### 封じ込め

乱数源を注入する。`rng: () => number` や id 生成関数を引数で受け取り、本番は `Math.random`/`randomUUID`、テストは**固定 seed の擬似乱数**か定数を渡す。
「ランダムな id が返る」こと自体を検証したいなら、値の一致でなく形式(長さ・一意性・パターン)を検証する。

### TypeScript example

悪い例(生成 id に依存し、実行ごとに別物になる):

```ts
// cart.ts
import { randomUUID } from "node:crypto";
export function newCart() {
  return { id: randomUUID(), items: [] }; // 値を固定できない
}
```

直した例(id 生成を注入し、テストは決定的な源を渡す):

```ts
// cart.ts
export function newCart(genId: () => string = () => crypto.randomUUID()) {
  return { id: genId(), items: [] as string[] };
}

// cart.test.ts
import { describe, it, expect } from "vitest";
import { newCart } from "./cart";

describe("newCart: id 生成を固定する", () => {
  it("注入した id を使う", () => {
    let n = 0;
    const genId = () => `cart-${++n}`;
    expect(newCart(genId).id).toBe("cart-1");
    expect(newCart(genId).id).toBe("cart-2");
  });
});
```

---

## 並行・競合

### 原因

複数の非同期処理が共有状態へ同時に触れる、または完了順序が保証されない。
スケジューリングのわずかな差で書き込みが前後し、ある実行でだけ古い値を読む・二重に書く。負荷が高い CI でだけ再現するのが厄介な特徴だ。

### 検出法

並列度を上げて反復する。`Promise.all` で同じ操作を多重に同時発行し、回数を増やして回す。
CI の並列ワーカー数を上げる、マシン負荷を掛けた状態で回す、といった負荷の増幅でレース窓を広げる。1回の緑では競合は見えない。

### 封じ込め

共有状態への到達を直列化するか、順序を明示的に待ち合わせる。
排他(ロック、キュー、原子的操作)で競合区間を1つに絞るか、完了を `await` で確定させてから次へ進む。
ただし**並行・状態遷移・順序の設計の正しさはテストで全 interleaving を踏めない**。設計段階で `loop-engineering`(TLA+)を回して安全性・活性を検査し、反例トレースを回帰テストへ落とすのが根治になる。

### TypeScript example

悪い例(read→write が原子的でなく、同時実行で更新が消える):

```ts
// counter.ts
let value = 0;
export async function increment() {
  const cur = value;           // 読む
  await Promise.resolve();      // ここで他の実行が割り込む
  value = cur + 1;              // 書く(古い値に基づく)
}
export const read = () => value;
```

直した例(直列化して原子性を回復し、並列発行で検証する):

```ts
// counter.ts
let value = 0;
let chain: Promise<void> = Promise.resolve();
export function increment() {
  chain = chain.then(() => { value += 1; }); // 直列化
  return chain;
}
export const read = () => value;

// counter.test.ts
import { describe, it, expect } from "vitest";
import { increment, read } from "./counter";

describe("increment: 並列度を上げても取りこぼさない", () => {
  it("100 並列でも 100 になる", async () => {
    await Promise.all(Array.from({ length: 100 }, () => increment()));
    expect(read()).toBe(100);
  });
});
```

---

## テスト間順序・状態漏れ

### 原因

あるテストが残したグローバル状態(モジュール変数、DB レコード、環境変数、一時ファイル、モックの設定)を次のテストが踏む。
テストが特定の実行順序に暗黙依存し、単独では緑だが順番が変わると落ちる。並列実行や `.only` での絞り込みで初めて露呈する。

### 検出法

順序をシャッフルして実行する。ランナーの順序ランダム化(vitest の `sequence.shuffle`)を有効にし、seed を変えて複数回回す。
個別実行では緑なのに全体実行で赤、あるいはその逆になるテストは状態漏れの兆候。1テストだけ単独実行しても緑になるかを確かめる。

### 封じ込め

共有状態を持たない、または各テストで必ず初期化・後始末する。
`beforeEach` で初期状態を作り直し、`afterEach`(teardown)で確保したものを必ず解放する([`test-structure.md`](test-structure.md) の Four-Phase Test)。
グローバル可変状態・モジュールキャッシュ・環境変数は、テストごとにリセットするか、そもそも注入で渡して共有をやめる。

### TypeScript example

悪い例(モジュールレベルの状態がテスト間で漏れ、順序に依存する):

```ts
import { describe, it, expect } from "vitest";

const users: string[] = []; // テスト間で共有される

describe("users(状態漏れ)", () => {
  it("追加できる", () => {
    users.push("alice");
    expect(users).toHaveLength(1); // 単独なら緑
  });
  it("空のはず", () => {
    expect(users).toHaveLength(0); // 前のテスト次第で落ちる
  });
});
```

直した例(各テストで状態を作り直し、漏れを断つ):

```ts
import { describe, it, expect, beforeEach } from "vitest";

describe("users(各テストで初期化)", () => {
  let users: string[];
  beforeEach(() => {
    users = []; // 毎回まっさらから始める
  });

  it("追加できる", () => {
    users.push("alice");
    expect(users).toHaveLength(1);
  });
  it("空から始まる", () => {
    expect(users).toHaveLength(0);
  });
});
```

---

## 外部ネットワーク

### 原因

テストが実在の外部サービス(HTTP API、DNS、サードパーティ)へ実際に通信する。
相手の遅延・障害・レート制限・レスポンス変化・ネットワーク瞬断で、コードは正しいのにテストが落ちる。CI のネットワーク環境次第で結果が変わる。

### 検出法

ネットワークを遮断して実行する。テスト実行時に外向き通信を止める(オフライン、DNS をブロック、プロキシで遮断)と、外部へ出ているテストが落ちて炙り出される。
真に外部へ依存していないテストはネット遮断でも緑のままのはず。実時間で何百ミリ秒も掛かるテストも実通信の疑いがある。

### 封じ込め

外部依存をテストダブルへ置き換える。HTTP はモックサーバ(MSW など)やスタブで応答を固定し、テストが応答内容と異常系(タイムアウト、5xx、不正ボディ)を**決める**状態にする([`test-doubles.md`](test-doubles.md))。
本物のエンジンとの統合が要る管理下の依存(自前 DB など)は Testcontainers で固定する。真の外部サービスとの疎通確認は、少数の契約テスト・smoke テストに隔離する。

### TypeScript example

悪い例(実 API を叩き、相手の都合で落ちる):

```ts
// rate.ts
export async function getRate(): Promise<number> {
  const res = await fetch("https://api.example.com/usd-jpy");
  return (await res.json()).rate;
}
```

直した例(fetch をスタブ化し、応答を固定する):

```ts
// rate.test.ts
import { describe, it, expect, vi, afterEach } from "vitest";
import { getRate } from "./rate";

afterEach(() => vi.restoreAllMocks());

describe("getRate: 外部応答を固定する", () => {
  it("レートを取り出す", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ rate: 155.5 })),
    );
    expect(await getRate()).toBe(155.5);
  });
});
```

---

## タイマー・sleep

### 原因

テストが「N ミリ秒待てば処理が終わっているはず」という実時間 sleep に依存する。
待ち時間は実行環境の速度・負荷で変動するので、遅いマシンや混んだ CI でだけ「まだ終わっていない」状態で検証が走り落ちる。長めに取れば今度はテストが遅くなる。

### 検出法

実時間 sleep を検知する。テストコード中の `setTimeout` での固定待ち、`await sleep(ms)` の類を grep で洗い出す。
実行が一定時間きっかり掛かるテスト、CI でだけ稀に落ちる時間絡みのテストは固定 sleep を疑う。マシンを意図的に遅くして(負荷を掛けて)再現させる。

### 封じ込め

固定 sleep を禁止し、フェイクタイマーか条件待ちに置き換える。
タイマー駆動のロジックは `vi.useFakeTimers()` + `vi.advanceTimersByTime()` で時間を**仮想的に**進め、実時間を待たない。
完了を待つなら固定 sleep でなく、条件が満たされるまでのポーリング待ち(vitest の `expect.poll` / `vi.waitFor`)を使い、満たされ次第すぐ進む。

### TypeScript example

悪い例(実時間 sleep で完了を当てにし、遅い環境で落ちる):

```ts
import { describe, it, expect } from "vitest";
import { startJob, jobDone } from "./job";

it("ジョブが終わる(固定 sleep)", async () => {
  startJob();
  await new Promise((r) => setTimeout(r, 100)); // 100ms で足りる保証は無い
  expect(jobDone()).toBe(true);
});
```

直した例(条件が満たされるまでポーリングで待つ):

```ts
import { describe, it, expect, vi } from "vitest";
import { startJob, jobDone } from "./job";

it("ジョブが終わる(条件待ち)", async () => {
  startJob();
  await vi.waitFor(() => expect(jobDone()).toBe(true)); // 終わり次第すぐ進む
});
```

---

## 浮動小数

### 原因

浮動小数の計算結果を `===` / `toBe` で厳密等値比較する。
`0.1 + 0.2 === 0.3` が偽になるように、二進浮動小数の丸め誤差で末尾がわずかにずれる。入力値・演算順序・最適化の差で、ある実行でだけ最終ビットが食い違い落ちる。

### 検出法

浮動小数の等値比較を検知する。浮動小数を返す計算に対する `toBe` / `===` を洗い出し、許容誤差なしで比較している箇所を疑う。
入力や演算順序を変えて反復すると、誤差の出方が変わって等値比較が破れる組合せがあぶり出される。

### 封じ込め

許容誤差を伴う比較に替える。vitest なら `toBeCloseTo(expected, digits)` を使い、意味的に許せる桁数で比較する。
通貨など丸め誤差が許されないものは、そもそも浮動小数でなく整数(最小単位)や十進数で持つのが根治になる。

### TypeScript example

悪い例(丸め誤差で厳密等値が破れる):

```ts
import { describe, it, expect } from "vitest";

it("0.1 + 0.2 は 0.3(厳密等値)", () => {
  expect(0.1 + 0.2).toBe(0.3); // 落ちる: 0.30000000000000004
});
```

直した例(許容誤差で比較する):

```ts
import { describe, it, expect } from "vitest";

it("0.1 + 0.2 は 0.3(許容誤差)", () => {
  expect(0.1 + 0.2).toBeCloseTo(0.3, 10);
});
```

---

## 共通方針(隔離・検出の総論)

### 見つけた flaky は隔離して原因を特定する

flaky を見つけたら、まず**隔離(quarantine)**して原因を特定する。本流の緑を汚さないよう一時的に分離はしてよいが、それは**原因究明までの猶予**であって、放置の口実にしない。
やってはいけないのは、retry(自動再実行)で落ちを握り潰して緑に見せる**緑詐称**だ。retry は非決定性を隠すだけで根治しないどころか、本物の退行まで覆い隠す。原因を上記いずれかの要因に突き止め、検出法で再現させ、封じ込めで断つところまでを1サイクルにする。

### 検出の総論

flaky は1回の緑では見えない。揺らぎを意図的に増幅して再現させるのが検出の要諦で、軸は3つある。

- **seed を変えて反復する**：乱数・property-based・メタモルフィックは seed を振って多数回回す。特定 seed の最小反例を回帰へ固定する。
- **順序をシャッフルして実行する**:テスト実行順をランダム化し、状態漏れ・順序依存を露呈させる。単独実行と全体実行の食い違いを見る。
- **並列度を上げる**:同時実行数・マシン負荷を上げてレース窓を広げ、競合と実時間 sleep を炙り出す。

封じ込めの共通の型は、**非決定性の源をテストの制御下へ引き込む**ことに尽きる。時刻・乱数は注入して固定し、外部依存はダブルへ置き換え、実時間待ちはフェイクタイマーか条件待ちにし、共有状態は初期化・後始末で断つ。テストが結果を**決められる**状態にできたとき、flaky は消える。
