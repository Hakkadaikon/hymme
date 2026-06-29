# テストの flaky(外部依存・実時間の非決定性)の体系的対策

同じテストが走らせるたびに緑赤を行き来する flaky のうち、**外部サービスとの通信**と**実時間の経過待ち**に由来する要因(外部ネットワーク、タイマー・sleep)を扱う。
これらは「テストの外にある相手の都合」と「環境ごとに変わる実時間」をテストが制御できていないことから生じる。

協調の非決定性(並行・競合、テスト間順序・状態漏れ)と検出・隔離の総論は [`flakiness-concurrency.md`](flakiness-concurrency.md)、値の非決定性(時刻・乱数・浮動小数)は [`flakiness-value.md`](flakiness-value.md) を参照。

各要因は **原因 / 検出法 / 封じ込め / TypeScript example(悪い例→直した例) / 完了チェック** で示す。
検出は「たまたま緑」を破るために**意図的に揺らぎを増幅して再現させる**(再現コマンドと反復回数を必ず添える)。
封じ込めは揺らぎの源をテストの制御下へ引き込む(ダブルへ置き換える、フェイクタイマー・条件待ちにする)。

相互参照:

- 外部依存をテストダブルへ置き換える使い分けは [`test-doubles.md`](test-doubles.md) を参照。
- 後始末漏れによる状態汚染の構成は [`test-structure-lifecycle.md`](test-structure-lifecycle.md) の Four-Phase Test(teardown)を参照。

## 目次

- [外部ネットワーク](#外部ネットワーク)
- [タイマー・sleep](#タイマー・sleep)

---

## 外部ネットワーク

### 原因

テストが実在の外部サービス(HTTP API、DNS、サードパーティ)へ実際に通信する。
相手の遅延・障害・レート制限・レスポンス変化・ネットワーク瞬断で、コードは正しいのにテストが落ちる。CI のネットワーク環境次第で結果が変わる。

### 検出法

ネットワークを遮断して、外へ出ているテストを落として炙り出す。

1. **外向き通信を止めて回す**:オフライン、DNS ブロック、プロキシ遮断のいずれかで外部を断ち、`vitest run` する。外部へ出ているテストが落ちて露呈する。
2. **未モック通信を即エラー化する**:MSW なら `onUnhandledRequest: "error"` を設定し、想定外の実通信があれば即落とす(`grep -rn 'onUnhandledRequest' .` で設定の有無を確認)。
3. **実時間の長いテストを疑う**:1テストに数百ミリ秒以上掛かるものは実通信の疑い。`vitest run --reporter=verbose` で所要時間を見る。
4. **再現コマンド**:ネット遮断下で `vitest run --repeat=20`。真に外部非依存なら全緑のはず。1つでも赤なら実通信が残っている。

### 封じ込め

外部依存をテストダブルへ置き換える。

1. **応答を固定する**:HTTP はモックサーバ(MSW など)やスタブで応答を固定し、テストが応答内容を**決める**状態にする([`test-doubles.md`](test-doubles.md))。
2. **異常系も決め打つ**:タイムアウト、5xx、不正ボディ、レート制限をダブルで再現し、異常系のテストを揃える。
3. **管理下の依存は本物で**:自前 DB など管理下のプロセス外依存は Testcontainers で本物のエンジンに繋ぐ([`test-doubles.md`](test-doubles.md) の Testcontainers)。
4. **真の疎通は隔離する**:本物の外部サービスとの疎通確認は、少数の契約テスト・smoke テストに隔離し、通常スイートから外す。

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

### 完了チェック(もれ確認)

- **未モック通信が即エラーになるか**:MSW 等で `onUnhandledRequest: "error"` が設定され、想定外の実通信が落ちる構成か。
- **異常系がダブルで揃っているか**:タイムアウト・5xx・不正ボディ・レート制限の各異常系に、ダブルで再現したテストが対応しているか(正常系だけで閉じていないか)。
- **ネット遮断で全緑か**:外向き通信を遮断した状態で `vitest run --repeat=20` が全緑。1つでも赤なら通常スイートに実通信が残る。
- **真の疎通が隔離されているか**:本物の外部を叩くテストが、通常スイートと別タグ(契約/smoke)に分離され、CI で skip 握り潰しになっていないか。
- **封じ込め完了の判定**:ネット遮断 ×20 反復が連続全緑、未モック通信がエラー化、真の疎通が別スイートに隔離されたとき封じ込め完了とみなす。

---

## タイマー・sleep

### 原因

テストが「N ミリ秒待てば処理が終わっているはず」という実時間 sleep に依存する。
待ち時間は実行環境の速度・負荷で変動するので、遅いマシンや混んだ CI でだけ「まだ終わっていない」状態で検証が走り落ちる。長めに取れば今度はテストが遅くなる。

### 検出法

実時間 sleep を静的に洗い出し、遅い環境で再現させる。

1. **固定待ちを grep で洗う**:`grep -rnE 'setTimeout\(|sleep\(|delay\(|await new Promise' <test>` で実時間待ちを列挙する。テスト内の固定 sleep はすべて疑う。
2. **きっかり一定時間のテストを疑う**:`vitest run --reporter=verbose` で所要時間が固定待ちと一致するテストを探す。
3. **遅い環境で再現する**:マシンに負荷を掛ける、CPU を絞る(`cpulimit` 等)状態で `vitest run --repeat=50` し、間に合わずに落ちる固定 sleep を炙り出す。
4. **再現コマンド**:負荷下で `vitest run path/to.test.ts --repeat=50`。1つでも赤なら固定 sleep に依存している。

### 封じ込め

固定 sleep を禁止し、フェイクタイマーか条件待ちに置き換える。

1. **タイマー駆動はフェイクで進める**:`vi.useFakeTimers()` + `vi.advanceTimersByTime(ms)` で仮想時間を進め、実時間を待たない。`afterEach(() => vi.useRealTimers())` で戻す。
2. **完了待ちは条件待ちにする**:固定 sleep でなく `expect.poll` / `vi.waitFor` で条件が満たされ次第すぐ進む。
3. **固定 sleep をコードベースから消す**:検出法1の grep がテスト対象/テストでゼロになるまで置き換える。

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

### 完了チェック(もれ確認)

- **固定 sleep が残っていないか**:`grep -rnE 'setTimeout\(r,|sleep\(|delay\(' <test>` がゼロか。残ったヒットがフェイクタイマー管理下か条件待ちに直っているか逆引きする。
- **フェイクタイマーが戻されているか**:`vi.useFakeTimers()` に対し `vi.useRealTimers()` が `afterEach` で対応しているか(戻し忘れは他テストへ漏れる)。
- **負荷下で全緑か**:CPU を絞る/別負荷を掛けた状態で `vitest run --repeat=50` が全緑。
- **封じ込め完了の判定**:テスト内の固定 sleep が grep でゼロ、負荷下 ×50 反復が連続全緑になったとき封じ込め完了とみなす。

---

協調の非決定性(並行・競合、テスト間順序・状態漏れ)と検出・隔離の総論は [`flakiness-concurrency.md`](flakiness-concurrency.md)、値の非決定性(時刻・乱数・浮動小数)は [`flakiness-value.md`](flakiness-value.md) を参照。
