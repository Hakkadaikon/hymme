# ランダム入力を生成して性質と頑健性を叩くテスト

人間が個別のケースを書き並べる代わりに、入力を自動生成して性質や頑健性をライブラリに叩かせるテスト群。
古典のブラックボックス技法が「この入力でこの出力」を1つずつ固定するのに対し、ここでは「どんな入力でも成り立つ関係」や「どんな入力でも壊れないこと」を多数のランダム入力で確かめる。

これらは入力生成を機械に任せる点で共通する。
性質(不変条件)で縛る(PBT)、不正な入力で頑健性を試す(ファジング、カバレッジガイデッドファジング)、パラメータの組合せを小さな集合で覆う(コンビナトリアル)という、生成の狙いの違いで整理する。

## 目次

- [プロパティベーステスト(Property-Based Testing)](#プロパティベーステストproperty-based-testing)
- [ファジング(Fuzzing)](#ファジングfuzzing)
- [カバレッジガイデッドファジング(Coverage-Guided Fuzzing)](#カバレッジガイデッドファジングcoverage-guided-fuzzing)
- [コンビナトリアルテスト(Combinatorial Testing)](#コンビナトリアルテストcombinatorial-testing)
- [oracle を別の参照で代替する手法は別ファイルへ](#oracle-を別の参照で代替する手法は別ファイルへ)
- [AI と非決定的出力は別ファイルへ](#ai-と非決定的出力は別ファイルへ)

---

## プロパティベーステスト(Property-Based Testing)

### 概要
個別の入力例ではなく、入力全体に対して成り立つべき性質(不変条件)を宣言し、ライブラリが多数のランダム入力を生成して反例を探す。

### 目的/いつ使う
「逆関数の往復で元に戻る」「可換」「結果は常にソート済み」のように、出力そのものより入力と出力の関係を言えるときに使う。
反例が見つかると自動で最小化(shrink)され、最小の壊れる入力が手に入る。
逆に成り立つ性質が「実装をそのまま書き写しただけ」になるなら oracle になっておらず、無価値なので使わない。

### TypeScript example
JSON エンコード/デコードの往復(round-trip)を性質として叩く。

```ts
import { describe, it, expect } from "vitest";
import fc from "fast-check";
import { encode, decode } from "./codec";

describe("codec: properties", () => {
  it("round-trips any value (decode . encode = id)", () => {
    fc.assert(
      fc.property(fc.jsonValue(), (value) => {
        expect(decode(encode(value))).toStrictEqual(value);
      }),
    );
  });
});
```

### 落とし穴
- 生成器が狭いと(正の整数だけ等)肝心の境界値や異常値を踏まず、緑なのに穴が残る。`fc.jsonValue` のように広い生成器を選ぶ。
- 性質が実装の写し(同じロジックで期待値を作る)になると、両方同時に間違っても通る。
- 性質は正しいのに**比較の等価判定**が落とし穴になる。広い生成器は `-0`、`+0`、`NaN`、極小差の浮動小数を踏むので、`toBe`(`Object.is`)は `-0` と `+0` を別物と判定し、`NaN === NaN` は常に偽になる。数値の性質では `===` や許容誤差つき比較を選び、何を等価とみなすかを性質の一部として決める。手法が正しくても等価判定がずれると flaky に落ちる。

### 網羅の定義
- **網羅基準**：対象の正しさを縛る性質(不変条件)集合を全て property 化し、各 property を十分広い生成器で多数試行して反例ゼロ。
- **網羅手順**：
  1. 対象に成り立つ性質を列挙する(往復、可換、不変、結果制約)。
  2. 各性質を `fc.property` のアサーションへ落とす。
  3. 生成器を入力空間に合わせて広く取る(狭い生成器は穴を残す)。
- **達成チェック**：生成器が境界値と異常値を踏むか確認する。性質が実装の写しになっていないか(独立した oracle として成立しているか)を見る。

---

## ファジング(Fuzzing)

### 概要
不正、極端、ランダムなバイト列や文字列を大量に流し込み、クラッシュ、ハング、assertion 違反、未処理例外を起こす入力を探す。

### 目的/いつ使う
パーサー、デシリアライザ、入力検証、ファイル/プロトコル境界など「信頼できない入力」を受ける箇所の頑健性を確かめる。
判定は「壊れないこと」(落ちない、無限ループしない、不変条件を保つ)で済むので、出力の正解が要らないのが利点。
出力の意味的正しさまで問いたいなら、ファジングではなく PBT やメタモルフィックを使う。

### TypeScript example
fast-check をファザーとして使い、任意文字列でパーサーが例外を投げず必ず判定を返すことを確認する。

```ts
import { describe, it, expect } from "vitest";
import fc from "fast-check";
import { parseConfig } from "./config";

describe("parseConfig: fuzzing", () => {
  it("never throws and always returns ok|error for any string", () => {
    fc.assert(
      fc.property(fc.string(), (raw) => {
        const r = parseConfig(raw); // 例外を投げたらここで失敗扱い
        expect(r.kind === "ok" || r.kind === "error").toBe(true);
      }),
    );
  });
});
```

### 落とし穴
- 「落ちない」だけを見ると、黙って誤った値を返すバグはすり抜ける。不変条件チェックを併せて入れる。
- 反例の再現にはシード固定が要る。fast-check は失敗時にシードを出すので控える。

### 網羅の定義
- **網羅基準**：信頼できない入力境界に対し、クラッシュ、ハング、未処理例外、不変条件違反を起こす入力が見つからない状態(到達した分岐とコーパスで近似)。
- **網羅手順**：
  1. 入力源を fast-check 等で広く生成する。
  2. 「落ちない、必ず判定を返す、不変条件を保つ」を assert する。
  3. 失敗時はシードを保存し回帰の種にする。
- **達成チェック**：「落ちない」だけでなく不変条件チェックを併載しているか確認する(黙って誤値を返すバグはこれが無いとすり抜ける)。

---

## カバレッジガイデッドファジング(Coverage-Guided Fuzzing)

### 概要
実行時のコードカバレッジを計測し、新しい経路を開拓した入力を「種」として残して変異させる。
ランダムな総当たりより遥かに速く深いパスへ到達する(AFL/libFuzzer 系の発想)。

### 目的/いつ使う
パーサーやバイナリ処理など分岐が深く、素朴なランダム入力では奥まで届かない対象に使う。
JS/TS では `@jazzer.js` や `jsfuzz` がカバレッジ計装つきのファザーを提供する。
分岐が浅く入力空間も狭いなら、計装のコストに見合わないので通常のファジングや PBT で足りる。

### TypeScript example
`@jazzer.js` のファズターゲットの最小形(専用ランナー `jazzer` で起動し、コーパスを育てる)。

```ts
// fuzz/parse.fuzz.ts  ->  npx jazzer fuzz/parse.fuzz.ts
import { FuzzedDataProvider } from "@jazzer.js/core";
import { parseConfig } from "../config";

export function fuzz(data: Buffer) {
  const provider = new FuzzedDataProvider(data);
  const raw = provider.consumeRemainingAsString();
  const r = parseConfig(raw);
  // 不変条件: 必ず判定が返る。破れたら throw してクラッシュ扱いにする
  if (r.kind !== "ok" && r.kind !== "error") throw new Error("invalid result");
}
```

### 落とし穴
- 計装つき実行は通常のユニットテストと別ランナー、別 CI ジョブになる。常時 CI に乗せるか、夜間ジョブに回すか先に決める。
- 育てたコーパスを捨てると毎回ゼロから探索になる。コーパスは保存して回帰の種に使う。

### 網羅の定義
- **網羅基準**：新規経路を開拓する入力が枯れる(カバレッジが頭打ちになる)まで探索し、育てたコーパスで網羅を近似する。
- **網羅手順**：
  1. `jazzer.js` 等でコードを計装する。
  2. ファズターゲットを定義する。
  3. コーパスを育て、新しい経路が出なくなるまで回す。
- **達成チェック**：計装ランナーを別 CI ジョブに分けているか、コーパスを保存して回帰の種にしているかを確認する。

---

## コンビナトリアルテスト(Combinatorial Testing)

### 概要
複数のパラメータが取り得る値の全組合せではなく、任意の t 個のパラメータの値の組合せを必ず一度は含む小さな集合(t-way / covering array)を自動生成する。

### 目的/いつ使う
設定フラグ、対応環境、入力カテゴリなど独立パラメータが多く、全組合せが爆発するときに使う。
欠陥の多くは少数パラメータの相互作用で起きるという経験則により、2-way(pairwise)で大半を、3-way で更に深い相互作用を、現実的なケース数で押さえる。
パラメータ間に強い依存(ある値が別の値を無効化する)があるなら制約を入れずに使うと無効ケースを量産するので、制約対応の生成器が要る。

### TypeScript example
`@fast-check/vitest` などにある pairwise 生成を使い、3パラメータの 2-way 組合せを回す。

```ts
import { describe, it, expect } from "vitest";
import { pairwise } from "./pairwise"; // covering array を返す小関数 or ライブラリ

const os = ["linux", "mac", "win"] as const;
const node = ["18", "20", "22"] as const;
const mode = ["dev", "prod"] as const;

describe("build matrix: 2-way coverage", () => {
  it.each(pairwise(os, node, mode))("builds on %s/node%s/%s", (o, n, m) => {
    expect(build({ os: o, node: n, mode: m }).ok).toBe(true);
  });
});
```

### 落とし穴
- t を上げるほどケース数が急増する。まず 2-way で測り、相互作用バグが残る箇所だけ 3-way に上げる。
- 無効な値の組合せを除外する制約を入れないと、生成されたケースの多くが意味を成さない。

### 網羅の定義
- **網羅基準**：選んだ強さ t に対する t-way covering array が全ての t-組合せを含む(まず 2-way、相互作用が疑わしい箇所だけ 3-way)。
- **網羅手順**：
  1. パラメータと値域を洗い出す。
  2. 無効組合せを除く制約を定義する。
  3. t-way covering array を生成し、各行を1ケースにする。
- **達成チェック**：制約で無効組合せを除外しているか確認する。t を上げる範囲を、相互作用バグの残る箇所に絞れているかを見る。

---

## oracle を別の参照で代替する手法は別ファイルへ

正解を直接持たないまま、別の参照や関係で正しさを判定する手法(スナップショット、承認テスト、差分テスト、メタモルフィックテスト、モデルベーステスト、形式検証連携)は、[modern-oracle.md](modern-oracle.md) にまとめた。

---

## AI と非決定的出力は別ファイルへ

テストを書く道具としての LLM(AI/LLM 支援テスト生成)と、製品に組み込まれた非決定的出力そのものの検証(階層化品質設計)は、[`ai-nondeterministic.md`](ai-nondeterministic.md) にまとめた。
