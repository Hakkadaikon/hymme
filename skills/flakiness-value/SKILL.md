---
name: flakiness-value
description: >
  テストが flaky になる原因のうち、値そのものが実行ごとに変わる非決定性(時刻/now・Date、
  乱数・UUID、浮動小数の丸め誤差)を検出・封じ込めする手法を扱う。
  test-catalog の手法カタログの一部。時刻依存の境界固定、乱数/UUID の注入とseed反復、
  浮動小数の許容誤差比較(toBeCloseTo)を検証したい、または割り当てたいときに使う。
  通常は test-catalog スキルの索引経由で手法が選定された後にこのスキルを直接参照する。
disable-model-invocation: true
---

# テストの flaky(値の非決定性)の体系的対策

同じコードに対して同じテストが、走らせるたびに緑になったり赤になったりする状態を flaky と呼ぶ。
flaky テストは「赤を信用できない」状態を生み、本物の退行をノイズに埋もれさせ、緑を retry で握り潰す悪習を招く。
原因はほぼ常に**テストが制御していない非決定性**にある。

このファイルは flaky のうち、**値そのものが実行ごとに変わる**要因(時刻、乱数・UUID、浮動小数)を扱う。
**協調の非決定性**(並行・競合、テスト間順序・状態漏れ、外部ネットワーク、タイマー・sleep)と、両者に共通する**総論**(隔離 quarantine、retry 緑詐称の戒め、検出の3軸)は [`flakiness-concurrency.md`](../flakiness-concurrency/SKILL.md) を参照。

各要因は **原因 / 検出法 / 封じ込め / TypeScript example(悪い例→直した例) / 完了チェック** で示す。
検出は「たまたま緑」を破るために**意図的に揺らぎを増幅して再現させる**(再現コマンドと反復回数を必ず添える)。
封じ込めは揺らぎの源をテストの制御下へ引き込む(注入する、固定する)。
**完了チェック**は「封じ込め完了」と言える機械的判定で、何回連続緑なら閉じるかと、取りこぼしの逆引きを定める。

相互参照:

- 外部依存をテストダブルへ置き換える使い分けは [`test-doubles.md`](../test-doubles/SKILL.md) を参照。
- property-based / メタモルフィックな seed 反復は [`good-test-principles.md`](../good-test-principles/SKILL.md) / [`test-design-quality.md`](../test-design-quality/SKILL.md) の脆さの議論と接続する。失敗 seed の最小反例の固定は [`generative-property.md`](../generative-property/SKILL.md)。
- 協調の非決定性と総論は [`flakiness-concurrency.md`](../flakiness-concurrency/SKILL.md)。

## 目次

- [時刻依存(now / Date)](#時刻依存now--date)
- [乱数・UUID](#乱数・uuid)
- [浮動小数](#浮動小数)

---

## 時刻依存(now / Date)

### 原因

コードが `Date.now()` や `new Date()` を内部で直接呼ぶと、出力が実行時刻に依存する。
「今日の日付」「24時間以内か」「タイムゾーンを跨ぐ深夜」などは、実行する時刻・曜日・タイムゾーンで結果が変わり、特定の時間帯やうるう日・月末でだけ落ちる。

### 検出法

時刻を機械的に進めて反復し、危険な時刻でだけ落ちる挙動をあぶり出す。

1. **疑わしい時刻を列挙する**：深夜直前(`23:59:59`)、月末→翌月、うるう日(`02-29`)、年跨ぎ(`12-31`→`01-01`)、サマータイム切替、扱う各タイムゾーンの日付境界。これが固定値で踏むべき境界一覧になる。
2. **各時刻へ時計を置いて回す**：`vi.setSystemTime(new Date("2026-02-28T23:59:59Z"))` のように列挙した時刻へ時計を固定し、`it.each` で全境界を1スイートで踏む。
3. **「現在時刻依存」を炙り出す**：固定せずに走らせるテストを、ローカルでも CI と違う時間帯・タイムゾーンで反復する。`TZ=America/New_York vitest run --repeat=20` と `TZ=Asia/Tokyo vitest run --repeat=20` で結果が変わるなら、テストが現在時刻に依存している証拠。
4. **再現コマンド**：`TZ=UTC vitest run path/to.test.ts --repeat=50` を複数 TZ で。1つでも赤が出れば時刻依存が残っている。

### 封じ込め

時刻をテストの制御下に置く。

1. **時計を注入する(根治)**：`now: () => Date` のような時刻源を引数やコンストラクタで受け取り、本番は `Date.now`、テストは固定値を渡す。コード内の `Date.now()` / `new Date()` 直呼びをこの注入点へ集約する。
2. **注入できないときはフェイク時計**：既存コードに手を入れにくいなら `vi.useFakeTimers()` + `vi.setSystemTime(fixed)` でグローバルな時計を固定し、`afterEach(() => vi.useRealTimers())` で必ず戻す。
3. **境界を固定値で踏む**:検出法1で列挙した各境界を、固定時刻のテストとして残す(回帰)。
4. いずれも、テストが時刻を**決める**状態にする。

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

### 完了チェック(もれ確認)

- **時刻直呼びが残っていないか**:`grep -rnE 'Date\.now\(\)|new Date\(\)' src/` の各ヒットが、時計注入点(`now` 引数)かフェイク時計の管理下にあるかを逆引きする。テスト対象コードに裸の直呼びが残れば未封じ込め。
- **境界を固定で踏んだか**:検出法1で列挙した境界(深夜直前・月末・うるう日・年跨ぎ・各 TZ)のそれぞれに固定時刻テストが対応しているか。台帳の境界 ID とテスト名で1対1に逆引きする。
- **TZ を変えて全緑か**:`TZ=UTC`、`TZ=Asia/Tokyo`、`TZ=America/New_York` の3つ以上で各 `vitest run --repeat=50` が全緑。1つでも赤が出れば現在時刻依存が残る。
- **封じ込め完了の判定**:上記3 TZ × 50 回が連続全緑で、かつ裸の `Date.now()`/`new Date()` が対象コードから消えたとき封じ込め完了とみなす。

---

## 乱数・UUID

### 原因

`Math.random()` や `crypto.randomUUID()` をコード内で直接呼ぶと、生成値が毎回変わる。
たまたま衝突しない値で緑になり、ある実行でだけ衝突・並び順違い・特定値で落ちる。アサーションが生成値そのものに依存していると、再現すらできない。

### 検出法

seed を変えて反復し、特定 seed でだけ落ちる組合せをあぶり出す。

1. **乱数源を差し替え可能にする**:検出のためにも、まず乱数源を引数で受け取れる形にする(封じ込めと同じ注入点)。
2. **多数の seed で反復する**:固定 seed の擬似乱数を `0..N` で振り、同じテストを多数回回す。`for s in (seq 0 199); SEED=$s vitest run path/to.test.ts; end`(fish)で 200 seed を踏み、1つでも赤を拾う。
3. **property-based で網羅探索する**:fast-check 等で多数ケースを生成し、失敗時に出る seed と最小反例を回帰として固定する([`generative-property.md`](../generative-property/SKILL.md))。`fc.assert(prop, { numRuns: 1000 })` のように実行数を上げる。
4. **再現コマンド**:`SEED=<失敗seed> vitest run path/to.test.ts` で最小反例を確定再現できることを確かめる。

### 封じ込め

乱数源を注入する。

1. **乱数源を引数で受け取る(根治)**:`rng: () => number` や id 生成関数を引数で受け取り、本番は `Math.random`/`randomUUID`、テストは**固定 seed の擬似乱数**か定数を渡す。
2. **裸の直呼びを注入点へ集約する**:コード内の `Math.random()` / `crypto.randomUUID()` 直呼びをすべて注入点経由に置き換える。
3. **「ランダムであること」自体の検証は形式で**:具体値でなく形式(長さ・一意性・パターン・分布)を検証する。値の一致に依存させない。

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

### 完了チェック(もれ確認)

- **乱数直呼びが残っていないか**:`grep -rnE 'Math\.random\(\)|randomUUID\(|randomBytes\(' src/` の各ヒットが注入点経由かを逆引きする。テスト対象に裸の直呼びが残れば未封じ込め。
- **生成値そのものへのアサートが無いか**:`grep -rn 'randomUUID\|Math.random' <test>` の周辺で、生成値の一致(`toBe(<具体的UUID>)`)を期待していないか。形式検証(長さ・パターン・一意性)に置き換わっているか。
- **seed を振って全緑か**:`for s in (seq 0 199); SEED=$s vitest run path/to.test.ts; or echo "RED seed=$s"; end` が 200 seed すべて緑。1つでも赤なら未封じ込め。
- **PBT の実行数が十分か**:property-based なテストの `numRuns` が(critical なら)1000 以上で、失敗 seed が回帰固定されているか。
- **封じ込め完了の判定**:200 seed 反復が連続全緑、PBT が `numRuns` 規定回で緑、裸の乱数直呼びが対象コードから消えたとき封じ込め完了とみなす。

---

## 浮動小数

### 原因

浮動小数の計算結果を `===` / `toBe` で厳密等値比較する。
`0.1 + 0.2 === 0.3` が偽になるように、二進浮動小数の丸め誤差で末尾がわずかにずれる。入力値・演算順序・最適化の差で、ある実行でだけ最終ビットが食い違い落ちる。

### 検出法

浮動小数の等値比較を検知し、入力・順序を変えて誤差の出方を変える。

1. **厳密等値を grep で洗い出す**:`grep -rnE 'toBe\(|toEqual\(|===' <test>` のうち、左辺が浮動小数を返す計算のものを疑う。許容誤差なし比較が候補。
2. **入力・演算順序を変えて反復する**:property-based で被加数の順序や値を振る(`fc.array(fc.float())` を合計して結合法則を踏む等)。誤差の出方が変わり、等値比較が破れる組合せがあぶり出される。
3. **再現コマンド**:`vitest run path/to.test.ts --repeat=50` と、PBT なら `numRuns` を上げる。順序入替で1つでも赤が出れば厳密等値が脆い。

### 封じ込め

許容誤差を伴う比較に替えるか、そもそも浮動小数で持たない。

1. **許容誤差比較にする**:vitest なら `toBeCloseTo(expected, digits)` を使い、意味的に許せる桁数で比較する。`toBe`/`===` を浮動小数結果に掛けない。
2. **丸め誤差が許されないものは整数/十進で持つ(根治)**:通貨は最小単位の整数(円・セント)か十進ライブラリで保持し、浮動小数計算を排除する。
3. 許容誤差の桁数は意味から決める(通貨なら桁を決め切る、科学計算なら有効桁)。

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

### 完了チェック(もれ確認)

- **浮動小数への厳密等値が残っていないか**:`grep -rnE 'toBe\(|===' <test>` の各ヒットで、左辺が浮動小数演算なら `toBeCloseTo` か整数/十進比較に直っているか逆引きする。
- **通貨が浮動小数で持たれていないか**:金額型が `number`(浮動小数)で持たれていないか。最小単位整数か十進型に直っているか(critical 経路では特に必須)。
- **順序入替で全緑か**:PBT で被演算子の順序・値を振った合計テストが `numRuns` 規定回(critical なら 1000 以上)で全緑、または `vitest run --repeat=50` で全緑。
- **封じ込め完了の判定**:対象コードに浮動小数への `toBe`/`===` が残らず、順序入替 PBT/反復が連続全緑になったとき封じ込め完了とみなす。

---

> 隔離(quarantine)・retry による緑詐称の戒め・検出の3軸(seed/順序/並列)といった**共通の総論**は [`flakiness-concurrency.md`](../flakiness-concurrency/SKILL.md#共通方針隔離検出の総論) にまとめてある。値の非決定性を封じ込めたら、そちらも併せて確認する。
