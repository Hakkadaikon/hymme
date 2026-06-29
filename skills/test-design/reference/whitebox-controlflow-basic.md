# ホワイトボックス技法とカバレッジ（制御フロー・基本系）

コードの内部構造を見て到達を測る制御フロー系のうち、命令・分岐・条件レベルの基本基準（C0、C1、条件網羅、判定/条件網羅）を扱う。
強さは C0 < C1 < 条件網羅 / 判定条件網羅 の順に上がる。各条件の独立影響まで見る MC/DC・多重条件網羅・経路系は [whitebox-controlflow-path.md](whitebox-controlflow-path.md) を参照。

カバレッジは到達の指標であって検証の指標ではない。通したことと正しさを確かめたことは別物で、その溝を埋める手法は [mutation-testing.md](mutation-testing.md) で扱う。
ループとデータの流れは [whitebox-dataflow-loop.md](whitebox-dataflow-loop.md) を参照。

## 目次

- [ステートメントカバレッジ（命令網羅 C0）](#ステートメントカバレッジ命令網羅-c0)
- [ブランチ/デシジョンカバレッジ（分岐網羅 C1）](#ブランチデシジョンカバレッジ分岐網羅-c1)
- [コンディションカバレッジ（条件網羅）](#コンディションカバレッジ条件網羅)
- [判定/条件網羅（Decision/Condition Coverage）](#判定条件網羅decisioncondition-coverage)

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
各条件の独立した効きまで示したいなら、一段上の MC/DC へ進む（[whitebox-controlflow-path.md](whitebox-controlflow-path.md)。その手前のレベルがここ）。

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
  各条件の独立影響までは保証しないので、それが要るなら [whitebox-controlflow-path.md](whitebox-controlflow-path.md) の MC/DC へ上げる。

---

各条件の独立影響を示す MC/DC、全組合せの多重条件網羅、経路系（パス・基底パス）は [whitebox-controlflow-path.md](whitebox-controlflow-path.md) を参照。
テスト自身の欠陥検出力は [mutation-testing.md](mutation-testing.md) で測る。
