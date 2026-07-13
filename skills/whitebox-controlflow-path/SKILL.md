---
name: whitebox-controlflow-path
description: >
  ホワイトボックス構造網羅のうち、各条件の独立影響を示す MC/DC(改良条件判定網羅)、
  全組合せを踏む多重条件網羅(Multiple Condition Coverage)、分岐の組合せを追う
  パスカバレッジ(経路網羅)、循環的複雑度で代表経路を選ぶ基底パステスト(McCabe Basis Path)を
  扱う。test-catalog の手法カタログの一部。複合条件の各条件が結果に独立して効くことを
  安全性クリティカルな判定で示したい、分岐の相互作用に起因するバグを狙いたい、経路数が
  爆発する対象で代表経路に絞りたいときに使う。通常は test-catalog スキルの索引経由で
  手法が選定された後にこのスキルを直接参照する。
disable-model-invocation: true
---

# ホワイトボックス技法とカバレッジ（制御フロー・経路と独立影響系）

制御フロー系のうち、各条件の独立影響を示す MC/DC、全組合せの多重条件網羅、分岐の組合せを追う経路系（パスカバレッジ、基底パステスト）を扱う。
基本系（C0、C1、条件網羅、判定/条件網羅）は [whitebox-controlflow-basic.md](../whitebox-controlflow-basic/SKILL.md) を参照。

カバレッジは到達の指標であって検証の指標ではない。その溝を埋める手法は [mutation-testing.md](../mutation-testing/SKILL.md) で扱う。
ループとデータの流れは [whitebox-dataflow-loop.md](../whitebox-dataflow-loop/SKILL.md) を参照。

## 目次

- [MC/DC（改良条件判定網羅）](#mcdc改良条件判定網羅)
- [多重条件網羅（Multiple Condition Coverage）](#多重条件網羅multiple-condition-coverage)
- [パスカバレッジ（経路網羅）](#パスカバレッジ経路網羅)
- [基底パステスト（McCabe Basis Path）](#基底パステストmccabe-basis-path)

## MC/DC（改良条件判定網羅）

### 概要
各条件が、他の条件を固定したまま単独で判定結果を反転させるという独立した影響を、1組のペアで示す網羅基準である。
DO-178C のレベル A（航空など安全性クリティカル）で要求される。

### 目的/いつ使う
複合条件の各条件が結果に独立して効くことを、組合せ爆発（全パターン 2ⁿ を踏む下の多重条件網羅）を避けつつ示したいときに使う。
n 条件で必要なケースは概ね n+1 と少なく、安全性が要る分岐ロジックに向く。
安全性要件の無い普通のアプリで全分岐にこれを課すのは過剰である（YAGNI）。critical な判定に絞る。

### TypeScript example
判定 `A && (B || C)` の真理値表と、各条件の独立影響を示す最小ケースセットを挙げる。
各条件について、その条件だけ反転すると結果も反転するペアを1組ずつ用意する。

| # | A | B | C | 結果 |
|---|---|---|---|------|
| 1 | T | T | F | T |
| 2 | F | T | F | F | （Aの独立影響: #1↔#2）
| 3 | T | F | F | F | （Bの独立影響: #1↔#3）
| 4 | T | F | T | T | （Cの独立影響: #3↔#4）

```ts
// guard.ts
export function guard(a: boolean, b: boolean, c: boolean): boolean {
  return a && (b || c);
}
```
```ts
// guard.test.ts
import { describe, it, expect } from "vitest";
import { guard } from "./guard";

// n=3 条件を 4 ケースで MC/DC 達成
describe("guard MC/DC", () => {
  it.each([
    { a: true,  b: true,  c: false, expected: true  }, // #1 基準
    { a: false, b: true,  c: false, expected: false }, // #2 Aの影響(#1と#2でAのみ差→結果反転)
    { a: true,  b: false, c: false, expected: false }, // #3 Bの影響(#1と#3でBのみ差→結果反転)
    { a: true,  b: false, c: true,  expected: true  }, // #4 Cの影響(#3と#4でCのみ差→結果反転)
  ])("a=$a b=$b c=$c -> $expected", ({ a, b, c, expected }) => {
    expect(guard(a, b, c)).toBe(expected);
  });
});
```

### 落とし穴
- 影響ペアは、対象条件だけが違い、他は同一で、結果が反転するという条件を満たす必要がある。ペアの選び方を誤ると MC/DC を満たさない。
- 短絡評価のある言語では、固定したつもりの条件が実際には評価されていないことがある。マスキング MC/DC か unique-cause MC/DC かを決めて扱う。

### 網羅の定義
- **網羅基準（いつ網羅完了とみなすか）**：各条件について「他の条件を固定したまま単独で判定結果を反転させる」独立影響ペアを1組ずつ示したとき（n条件で概ね n+1 ケース）。
- **網羅手順（基準を満たすケース集合の作り方）**：
  1. 判定の真理値表を作る（n条件で 2^n 行）。
  2. 各条件について「その条件だけ値が違い、他は同一で、結果が反転する」行のペアを1組選ぶ。
  3. 選んだペアの行を重複排除して最小ケースセットにまとめる。
- **達成チェック（漏れの検出）**：全条件に有効な影響ペアが揃い、短絡評価でマスキングされていないこと。
  手で組んだ真理値表とペアは、カバレッジツールの MC/DC レポート（対応していれば）や分岐レポートと突合し、`--coverage` で各ケースの到達を裏取りすると取り違えに気づける。
  安全性要件の無い分岐に全適用するのは過剰なので、critical な判定に絞る（YAGNI）。

## 多重条件網羅（Multiple Condition Coverage）

### 概要
判定内の全 atomic condition の真偽の全組合せ（n 条件なら 2ⁿ 通り）を、すべて踏むことを要求する最も強い条件系の基準である。

### 目的/いつ使う
条件どうしの相互作用に起因する欠陥まで、組合せを取りこぼさず潰したいときに使う。
MC/DC との違いを押さえる：**多重条件網羅は全条件の全組合せ（2ⁿ）を踏む。MC/DC は各条件が単独で判定結果を反転させる独立影響を示すだけで、線形（概ね n+1）で済む**。
2ⁿ が小さく収まる少条件の判定（2〜3 条件）でだけ現実的で、それ以上は MC/DC へ落とすのが定石である。

### TypeScript example
```ts
// guard.ts（MC/DC と同じ対象）
export function guard(a: boolean, b: boolean, c: boolean): boolean {
  return a && (b || c); // 条件: a, b, c
}
```
```ts
// guard.multi.test.ts
import { describe, it, expect } from "vitest";
import { guard } from "./guard";

// n=3 条件の全 2^3 = 8 組合せをすべて踏む（MC/DC の 4 ケースに対し倍）
describe("guard 多重条件網羅", () => {
  it.each([
    { a: false, b: false, c: false, expected: false },
    { a: false, b: false, c: true,  expected: false },
    { a: false, b: true,  c: false, expected: false },
    { a: false, b: true,  c: true,  expected: false },
    { a: true,  b: false, c: false, expected: false },
    { a: true,  b: false, c: true,  expected: true  },
    { a: true,  b: true,  c: false, expected: true  },
    { a: true,  b: true,  c: true,  expected: true  },
  ])("a=$a b=$b c=$c -> $expected", ({ a, b, c, expected }) => {
    expect(guard(a, b, c)).toBe(expected);
  });
});
```

### 落とし穴
- 条件数で 2ⁿ に爆発する。4 条件で 16、6 条件で 64 と現実的でなくなり、その手前で MC/DC へ切り替える。
- 短絡評価のある言語では、論理的に到達不能な組合せが出る（`a` が偽なら `a && ...` の後段は評価されない）。到達不能な行を無理に踏もうとしないこと。

### 網羅の定義
- **網羅基準（いつ網羅完了とみなすか）**：判定内の全 atomic condition の真偽の全組合せ（n 条件で 2ⁿ 通り）を、実現可能なものすべて踏んだとき。
- **網羅手順（基準を満たすケース集合の作り方）**：
  1. 判定の atomic condition を列挙し、真偽の全組合せ 2ⁿ 行の真理値表を作る。
  2. 短絡評価などで到達不能な組合せを除外する。
  3. 残った各組合せを通す入力を1ケースずつ用意する。
- **達成チェック（漏れの検出）**：実現可能な 2ⁿ 組合せに未踏が残っていないこと。
  手で起こした真理値表は、カバレッジツールの分岐レポートと突合し、`--coverage` で各組合せの到達を裏取りすると、到達不能行の取り違えや踏み漏れに気づける。
  条件数で爆発するので、2ⁿ が大きい判定では線形で済む MC/DC に切り替えているか見る。

## パスカバレッジ（経路網羅）

### 概要
制御フロー上の実行可能な経路（分岐の組合せ）を網羅する、最も強い構造基準である。

### 目的/いつ使う
分岐どうしの相互作用に起因するバグを狙うときに使う。
ただし経路数は分岐数に対して指数的に増え、ループがあれば事実上無限になるため、完全な経路網羅は通常は非現実的である。
実務では代表経路だけ選ぶ妥協が一般的で、その代表の選び方が下の基底パステスト（McCabe の循環的複雑度 = 線形独立な基底経路数）である。

### TypeScript example
```ts
// fee.ts
export function fee(member: boolean, weekend: boolean): number {
  let f = 100;
  if (member) f -= 30;     // 分岐1
  if (weekend) f += 50;    // 分岐2
  return f;
}
```
```ts
// fee.test.ts
import { describe, it, expect } from "vitest";
import { fee } from "./fee";

// 2分岐の全4経路を網羅（独立2分岐なので 2^2 = 4）
describe("fee 経路網羅", () => {
  it.each([
    { member: false, weekend: false, expected: 100 },
    { member: true,  weekend: false, expected: 70  },
    { member: false, weekend: true,  expected: 150 },
    { member: true,  weekend: true,  expected: 120 },
  ])("m=$member w=$weekend -> $expected", ({ member, weekend, expected }) => {
    expect(fee(member, weekend)).toBe(expected);
  });
});
```

### 落とし穴
- 経路数は分岐数に対し指数的。ループ込みでは完全網羅は不可能で、基底パスへの絞り込みが必須。
- 到達不能経路（条件が論理的に両立しない組合せ）を数えてカバレッジ率を下げてしまわないこと。

### 網羅の定義
- **網羅基準（いつ網羅完了とみなすか）**：理想は全実行可能経路を通したとき。ただし経路数は分岐に対して指数的に増え、ループがあれば無限になるため、完全網羅は非現実的。実務では下の基底パステストで代表経路に絞る。
- **網羅手順（基準を満たすケース集合の作り方）**：
  1. 独立した分岐が少なく全経路が現実的な数に収まるなら、各経路を通す入力を1ケースずつ用意する（上例の独立2分岐 → 4経路がこれ）。
  2. 経路数が爆発するなら完全網羅を諦め、下の基底パステストで代表経路を選ぶ。
- **達成チェック（漏れの検出）**：選んだ経路に到達不能経路（条件が論理的に両立しない組合せ）を数え込んでいないこと。爆発する対象で全経路網羅に固執していないこと。

## 基底パステスト（McCabe Basis Path）

### 概要
完全な経路網羅が非現実的なとき、McCabe の循環的複雑度 V(G) ぶんの線形独立な経路（基底パス）だけを選んで通す技法である。
基底パスを組み合わせれば任意の実行可能経路を表現できるので、全経路の代表として機能する。

### 目的/いつ使う
分岐が多く全経路網羅が現実的でないが、構造をある程度の強さで押さえたいときに使う。
V(G) は「最低これだけは独立な経路を通せ」という下限を与え、ケース数の根拠が思いつきでなく構造から決まる。
独立分岐が少なく全経路が小さく収まるなら、絞らずパス網羅で全経路を通せばよい（この絞り込みは不要）。

### TypeScript example
```ts
// classify.ts
export function classify(n: number): string {
  let label = "zero";
  if (n > 0) label = "pos";   // 分岐1
  if (n % 2 === 0) label += ":even"; // 分岐2
  return label;
}
```
```ts
// classify.test.ts
import { describe, it, expect } from "vitest";
import { classify } from "./classify";

// 2つの独立な if → V(G) = 2分岐 + 1 = 3。3本の線形独立な基底パスを通す
describe("classify basis path", () => {
  it.each([
    { n: -1, expected: "分岐1=偽, 分岐2=偽", out: "zero" },
    { n: 0,  expected: "分岐1=偽, 分岐2=真", out: "zero:even" },
    { n: 3,  expected: "分岐1=真, 分岐2=偽", out: "pos" },
  ])("n=$n ($expected)", ({ n, out }) => {
    expect(classify(n)).toBe(out);
  });
});
```

### 落とし穴
- V(G) はあくまで線形独立な基底経路の本数で、全実行可能経路の数ではない。基底パスを通しても、分岐の特定の組合せ（例：両分岐とも真）は明示的には踏まないことがある。相互作用が怪しい組合せは別途足す。
- 到達不能経路を基底に選ぶと本数が水増しされる。条件が論理的に両立しない経路は基底から除く。

### 網羅の定義
- **網羅基準（いつ網羅完了とみなすか）**：V(G) 本の線形独立な基底経路をすべて通したとき。
- **網羅手順（基準を満たすケース集合の作り方）**：
  1. 対象関数の制御フローグラフを描く。
  2. 循環的複雑度 V(G) = 辺 − 節点 + 2（連結成分1つの場合）を算出し、必要な基底経路数を出す。判定数 + 1 でも概算できる。
  3. その本数ぶん線形独立な経路を選び、各経路を通す入力を1ケースずつにする。
- **達成チェック（漏れの検出）**：選んだ経路が線形独立で本数（V(G)）を満たし、到達不能経路を数に入れていないこと。
  手で描いた制御フローグラフと選んだ経路は、カバレッジツールの分岐レポートと突合し、`--coverage` で各経路の到達を裏取りすると、数え間違いや踏み漏れに気づける。

---

基本系（C0、C1、条件網羅、判定/条件網羅）は [whitebox-controlflow-basic.md](../whitebox-controlflow-basic/SKILL.md) を参照。
ループとデータフローは [whitebox-dataflow-loop.md](../whitebox-dataflow-loop/SKILL.md)、テスト自身の欠陥検出力は [mutation-testing.md](../mutation-testing/SKILL.md) で扱う。
