# ホワイトボックス技法とカバレッジ

コードの内部構造（命令、分岐、条件、経路）を見て、どこまでテストが到達したかを測る技法群である。
何を検証すべきかをブラックボックスが決めるのに対し、ここではコードのどこを通したかを網羅基準にする。

ただしカバレッジは到達の指標であって、検証の指標ではない。
通したことと、正しさを確かめたことは別物である。
その溝を埋める手法は別ファイル（[mutation-testing.md](mutation-testing.md)）で扱う。

## 目次

- [ステートメントカバレッジ（命令網羅 C0）](#ステートメントカバレッジ命令網羅-c0)
- [ブランチ/デシジョンカバレッジ（分岐網羅 C1）](#ブランチデシジョンカバレッジ分岐網羅-c1)
- [コンディションカバレッジ（条件網羅）](#コンディションカバレッジ条件網羅)
- [判定/条件網羅（Decision/Condition Coverage）](#判定条件網羅decisioncondition-coverage)
- [MC/DC（改良条件判定網羅）](#mcdc改良条件判定網羅)
- [多重条件網羅（Multiple Condition Coverage）](#多重条件網羅multiple-condition-coverage)
- [パスカバレッジ（経路網羅）](#パスカバレッジ経路網羅)
- [基底パステスト（McCabe Basis Path）](#基底パステストmccabe-basis-path)
- [ループテスト（0回/1回/最大/境界回）](#ループテスト0回1回最大境界回)
- [データフローテスト（def-use 連鎖）](#データフローテストdef-use-連鎖)

## ステートメントカバレッジ（命令網羅 C0）

### 概要
すべての実行可能な命令文を最低1回実行したかを測る、最も緩い構造基準である。

### 目的/いつ使う
未到達コード（デッドコードや、テストし忘れた分岐の中身）の洗い出しに使う。
最低ラインの足切りとして CI に置く程度にとどめ、これ単体を品質目標にしてはいけない。
C0 100% でも、分岐の偽側を一度も通していない、条件式の評価結果を一度も確かめていない、という穴が普通に残る。

### TypeScript example
```ts
// grade.ts
export function grade(score: number): string {
  let label = "fail";        // 文1
  if (score >= 60) {
    label = "pass";          // 文2
  }
  return label;              // 文3
}
```
```ts
// grade.test.ts
import { describe, it, expect } from "vitest";
import { grade } from "./grade";

describe("grade C0", () => {
  // この1ケースで全3文を実行 = C0 100%
  // だが score < 60 の経路（if 偽）は一度も通っていない
  it("通過点で全文を踏む", () => {
    expect(grade(80)).toBe("pass");
  });
});
```

### 落とし穴
- C0 100% は「全部書いた」ではなく「全部の行に触れた」を意味するにすぎない。if の偽側は踏まずに 100% に達する。
- 三項演算子や短絡評価が1行に詰まっていると、行単位の計測では分岐の片側を見逃す。

### 網羅の定義
- **網羅基準（いつ網羅完了とみなすか）**：すべての実行可能文を最低1回実行したとき（C0=100%）。
- **網羅手順（基準を満たすケース集合の作り方）**：
  1. カバレッジ計測ツール（vitest `--coverage` や c8）を有効にして既存テストを走らせる。
  2. レポートで未実行（赤）の行を列挙する。
  3. その行に到達するケースを1本ずつ足し、再計測して赤が消えるまで繰り返す。
- **達成チェック（漏れの検出）**：計測レポートの未実行行が0であること。
  ただし C0 100% でも分岐の偽側を踏んでいない穴は残るので、足切りラインとして扱い品質目標にしない。

## ブランチ/デシジョンカバレッジ（分岐網羅 C1）

### 概要
各判定（if, while, switch, 三項）の真と偽の両方の分岐を、最低1回ずつ通したかを測る。

### 目的/いつ使う
C0 の主要な穴である分岐の片側未踏を埋める。
実務の構造カバレッジは、標準的な目標をここに置くことが多い。
注意：C1 は判定全体の真偽だけを見るので、`a || b` のような複合条件の中で個々の条件 `a` `b` がどう効いたかは問わない。
そこは条件網羅や MC/DC の領分である。

### TypeScript example
```ts
// discount.ts
export function discount(member: boolean, total: number): number {
  if (member && total >= 1000) {
    return total * 0.9;
  }
  return total;
}
```
```ts
// discount.test.ts
import { describe, it, expect } from "vitest";
import { discount } from "./discount";

describe("discount C1", () => {
  // 判定 (member && total>=1000) の真と偽を両方踏む
  it("真分岐: 会員かつ閾値以上", () => {
    expect(discount(true, 1000)).toBe(900);
  });
  it("偽分岐: 非会員", () => {
    expect(discount(false, 1000)).toBe(1000);
  });
});
```

### 落とし穴
- 判定の真偽は埋まっても、複合条件の各項の寄与は検証できていない。上例は `total>=1000` を偽にするケースが無くても C1 100% になりうる。
- switch の default を省くと未踏分岐が残りやすい。

### 網羅の定義
- **網羅基準（いつ網羅完了とみなすか）**：各判定（if/while/switch/三項）の真分岐と偽分岐を両方とも最低1回ずつ通したとき（C1=100%）。
- **網羅手順（基準を満たすケース集合の作り方）**：
  1. コード中の判定をすべて列挙し、各判定に真と偽の2マスを割り当てる。
  2. 各マスを踏む入力を選んでケースにする（switch は各 case と default を1マスずつ）。
  3. 計測ツールの branch coverage で未踏分岐を確認し、埋まるまでケースを足す。
- **達成チェック（漏れの検出）**：branch coverage が100%で、switch default の未踏マスが残っていないこと。
  ただし複合条件の各項がどう効いたかは C1 では測れないので、そこは条件網羅や MC/DC に委ねる。

## コンディションカバレッジ（条件網羅）

### 概要
判定を構成する個々の真偽条件（**atomic condition**）それぞれが、真と偽の両値を取ったかを測る。

### 目的/いつ使う
複合条件 `a && b`, `a || b` で、各オペランドが効いているかを確かめたいときに使う。
ただし条件網羅は各条件が両値を取ったことだけを要求し、判定全体の真偽が両方出ることは保証しない。
そのため C1 を満たさないケースセットでも条件網羅 100% になりうる（両方を満たす判定/条件カバレッジの形が安全である）。

### TypeScript example
```ts
// access.ts
export function canAccess(admin: boolean, active: boolean): boolean {
  return admin || active; // 条件: admin, active
}
```
```ts
// access.test.ts
import { describe, it, expect } from "vitest";
import { canAccess } from "./access";

describe("canAccess 条件網羅", () => {
  // admin: T/F、active: T/F を各々出す2ケース
  it("admin=T, active=F", () => {
    expect(canAccess(true, false)).toBe(true);
  });
  it("admin=F, active=T", () => {
    expect(canAccess(false, true)).toBe(true);
  });
  // 注意: この2ケースは「全体が偽(F,F)」を踏んでいない → 条件網羅100%でもC1未達
});
```

### 落とし穴
- 条件網羅だけでは判定全体の偽（または真）が欠ける場合がある。下の判定/条件網羅で両立させる。
- 短絡評価により後段の条件が評価されないことがある。評価された上で両値を取ったかを意識する。

### 網羅の定義
- **網羅基準（いつ網羅完了とみなすか）**：判定内の各 atomic condition が真と偽の両値を取ったとき。
- **網羅手順（基準を満たすケース集合の作り方）**：
  1. 複合条件を `&&` `||` で atomic condition に分解し、条件ごとに真と偽の2マスを並べる。
  2. 各条件の真と偽を踏む入力を選び、全条件のマスを埋めるようケースを組む。
  3. 短絡評価で評価到達しない条件が無いか確認し、到達する入力に直す。
- **達成チェック（漏れの検出）**：真と偽の未割当マスが残る条件が無いこと。
  ただし条件網羅100%でも判定全体の真偽が片方欠ける場合があるので、下の判定/条件網羅で両立させる。

## 判定/条件網羅（Decision/Condition Coverage）

### 概要
判定全体の真偽（C1）と、個々の atomic condition の真偽（条件網羅）を、どちらも両方踏むことを同時に要求する合成基準である。
C1 の「複合条件の各項の寄与を見ない」穴と、条件網羅の「判定全体の真偽が片方欠けうる」穴を、互いに塞ぎ合う。

### 目的/いつ使う
C1 だけ、または条件網羅だけでは取りこぼす両方の穴を、安価に同時に埋めたいときに使う。
MC/DC ほどの独立影響までは要らないが、C1 単独では弱い、という中間の保証が欲しい分岐に向く。
各条件の独立した効きまで示したいなら、一段上の MC/DC へ進む（その手前のレベルがここ）。

### TypeScript example
```ts
// access.ts（条件網羅と同じ対象）
export function canAccess(admin: boolean, active: boolean): boolean {
  return admin || active; // 判定: (admin || active) / 条件: admin, active
}
```
```ts
// access.test.ts
import { describe, it, expect } from "vitest";
import { canAccess } from "./access";

describe("canAccess 判定/条件網羅", () => {
  // 判定の真偽を両方 かつ admin/active の真偽も両方踏む
  it.each([
    { admin: true,  active: false, expected: true  }, // admin=T, 判定=T
    { admin: false, active: false, expected: false }, // active=F, 判定=F
    { admin: false, active: true,  expected: true  }, // active=T（残りの未割当マスを埋める）
  ])("admin=$admin active=$active -> $expected", ({ admin, active, expected }) => {
    expect(canAccess(admin, active)).toBe(expected);
  });
  // 条件網羅の2ケース(T,F)(F,T)に判定=Fを出す(F,F)を足すと、判定の真偽も両条件の真偽も揃う
});
```

### 落とし穴
- 「条件の真偽を埋めれば判定の真偽も埋まる」とは限らない。判定の真と偽が両方出ているかを、条件のマスとは別に必ず確認する。
- 短絡評価で後段の条件が評価されないと、条件側のマスが埋まったつもりで埋まっていない。評価到達する入力を選ぶ。
- 各条件が単独で判定を反転させる独立影響までは示せない。そこは MC/DC の領分で、判定/条件網羅100%でも MC/DC 未達はありうる。

### 網羅の定義
- **網羅基準（いつ網羅完了とみなすか）**：各判定の真分岐と偽分岐を両方踏み（C1）、かつ判定内の各 atomic condition が真と偽の両値を取った（条件網羅）とき、両方を同時に満たして網羅完了。
- **網羅手順（基準を満たすケース集合の作り方）**：
  1. C1 用に各判定へ真・偽の2マス、条件網羅用に各条件へ真・偽の2マスを並べる。
  2. 1ケースで複数のマスを同時に埋めるよう入力を選び、両方の全マスが埋まるまでケースを足す。
  3. 短絡評価で評価到達しない条件が無いか確認し、到達する入力に直す。
- **達成チェック（漏れの検出）**：判定の真偽マスと、全条件の真偽マスのいずれにも未割当が残っていないこと。
  各条件の独立影響までは保証しないので、それが要るなら下の MC/DC へ上げる。

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

## ループテスト（0回/1回/最大/境界回）

### 概要
ループの反復回数に着目し、0回、1回、典型回、最大回、最大±1回といった境界で挙動を確かめる技法である。

### 目的/いつ使う
オフバイワン、空入力、上限超過といったループ固有の欠陥を狙うときに使う。
配列処理、ページング、リトライ上限などに有効である。
全反復回数を試すのは無駄なので、0回、1回、境界に絞るのが要点である。

### TypeScript example
```ts
// sum.ts
export function sumFirstN(xs: number[], n: number): number {
  let s = 0;
  for (let i = 0; i < n && i < xs.length; i++) s += xs[i];
  return s;
}
```
```ts
// sum.test.ts
import { describe, it, expect } from "vitest";
import { sumFirstN } from "./sum";

describe("sumFirstN ループ境界", () => {
  it("0回: n=0", () => expect(sumFirstN([1, 2, 3], 0)).toBe(0));
  it("1回: n=1", () => expect(sumFirstN([1, 2, 3], 1)).toBe(1));
  it("最大(配列長で頭打ち): n>長", () => expect(sumFirstN([1, 2, 3], 99)).toBe(6));
  it("空入力でも落ちない", () => expect(sumFirstN([], 5)).toBe(0));
});
```

### 落とし穴
- ループ脱出条件の `<` と `<=` の取り違えは境界（最大±1）でしか露見しない。典型回だけでは見逃す。
- ネストループは内外の境界の組合せで考える。外側0回のとき内側が一度も実行されない経路を忘れない。

### 網羅の定義
- **網羅基準（いつ網羅完了とみなすか）**：各ループについて 0回、1回、典型回、最大回、最大±1回の反復を踏んだとき。ネストは内外の境界の組合せを踏んだとき。
- **網羅手順（基準を満たすケース集合の作り方）**：
  1. コード中のループを列挙し、各ループの反復回数の境界（0/1/最大/最大±1）を割り出す。
  2. 各境界回数になる入力を選んでケースにする。
  3. ネストループは外側の各境界 × 内側の各境界で組合せケースを作る。
- **達成チェック（漏れの検出）**：各ループに0回、1回、境界回のケースが揃い、外側0回で内側未実行の経路を踏んでいること。
  `<` と `<=` の取り違えは境界（最大±1）でしか出ないので、典型回だけで止めないこと。

## データフローテスト（def-use 連鎖）

### 概要
変数の定義（**def**：値の代入）から使用（**use**）までの連鎖を追い、各 def-use ペアを通すケースを設計する技法である。

### 目的/いつ使う
未初期化使用、代入したのに使われない値、再代入で上書きされる前提のロジックなど、データの流れに起因する欠陥を狙うときに使う。
制御フローだけでは見えない、どの代入がどの参照に届くかを検証したいときに有効である。

### TypeScript example
```ts
// pricing.ts
export function priceWith(taxRate: number, base: number): number {
  let price = base;            // def1: price
  if (taxRate > 0) {
    price = base * (1 + taxRate); // def2: price（条件付き再定義）
  }
  return price;                // use: price
}
```
```ts
// pricing.test.ts
import { describe, it, expect } from "vitest";
import { priceWith } from "./pricing";

describe("priceWith def-use", () => {
  // def1 -> use（再定義を通らず初期定義が届く経路）
  it("税率0: def1がuseに届く", () => {
    expect(priceWith(0, 100)).toBe(100);
  });
  // def2 -> use（条件付き再定義がuseに届く経路）
  it("税率>0: def2がuseに届く", () => {
    expect(priceWith(0.1, 100)).toBeCloseTo(110);
  });
});
```

### 落とし穴
- すべての def-use ペアの網羅はパス網羅に近づき高コスト。重要な変数（金額や権限フラグ）に絞る。
- 再代入で死ぬ def（どの use にも届かない代入）は、それ自体がバグの兆候。気づいたら設計を疑う。

### 網羅の定義
- **網羅基準（いつ網羅完了とみなすか）**：理想は全 def-use ペアを通す（all-uses）こと。
  ただし完全網羅はパス網羅に近づき高コストなので、実務は重要変数（金額や権限フラグ）の def-use ペアに絞って各1経路を通したとき。
- **網羅手順（基準を満たすケース集合の作り方）**：
  1. 対象変数の def（代入箇所）と use（参照箇所）をすべて列挙する。
  2. 各 def から各 use へ、途中で再定義されずに到達する def-use ペアを洗い出す。
  3. 各ペアに届く経路を1つ選び、その経路を通す入力をケースにする。
- **達成チェック（漏れの検出）**：重要変数の各 def-use ペアにケースが対応し、どの use にも届かない死んだ def が残っていないこと（残ればバグの兆候）。

## テストの強さは別ファイルへ

ここまでの構造カバレッジは、いずれもコードのどこを通したかを測る。
通したかどうかと、通した結果が正しいかをアサートで確かめたかどうかは別物である。
アサーションが甘ければ、高いカバレッジでもバグは漏れる。

テスト自身の欠陥検出力を測る手法は、[mutation-testing.md](mutation-testing.md) で扱う。
