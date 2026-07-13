---
name: mutation-testing
description: >
  test-catalog の手法カタログの一部。テストの強さを測る(mutation、ミューテーションテスト、
  テストの欠陥検出力、Killed/Survived/No coverage、Mutation Score、Stryker)ことを検証したい
  ときに使う。カバレッジ率が高いのにバグが漏れる状況の正体を暴く、アサーション不足を見つける
  ときに使う。通常は test-catalog スキルの索引経由で手法が選定された後にこのスキルを直接参照する。
disable-model-invocation: true
---

# ミューテーションテスト

カバレッジがコードへの到達を測るのに対し、ミューテーションテストはテスト自身の欠陥検出力を測る。
コードを壊したときにテストが落ちるかを問うことで、通したかどうかと正しさを確かめたかどうかの溝を埋める。

構造網羅（カバレッジ）の各手法は別ファイル（制御フロー系は [whitebox-controlflow-basic.md](../whitebox-controlflow-basic/SKILL.md) / [whitebox-controlflow-path.md](../whitebox-controlflow-path/SKILL.md)、データ・ループ系は [whitebox-dataflow-loop.md](../whitebox-dataflow-loop/SKILL.md)）で扱う。

## 目次

- [ミューテーションテスト（テストの強さを測るメタテスト）](#ミューテーションテストテストの強さを測るメタテスト)
- [まとめ: カバレッジの限界とミューテーションの位置づけ](#まとめ-カバレッジの限界とミューテーションの位置づけ)

## ミューテーションテスト（テストの強さを測るメタテスト）

### 概要
コードに意図的な小さな欠陥（**ミュータント**：`>` を `>=` に、`+` を `-` に、条件の反転など）を注入し、既存テストがそれを失敗として検出（kill）できるかを測る。
テストを試験する側のテストである。

### 目的/いつ使う
カバレッジ率が高いのにバグが漏れる、という状況の正体を暴くときに使う。

C0 と C1 は行や分岐を通したかしか見ず、通した結果が正しいかをアサートし忘れていても 100% になる。
ミューテーションはコードを壊したらテストが落ちるかを問うので、通過と検証が一致しない穴を直接突く。
生き残ったミュータント（survived）は、そのコードを壊してもどのテストも落ちなかった箇所であり、アサーション不足の証拠になる。

注意：計算コストが高い（ミュータント数 × テスト時間）。critical なモジュールに絞って回す。

### TypeScript example
最小の Stryker 設定。`@stryker-mutator/core` を使う。
```jsonc
// stryker.config.json
{
  "$schema": "./node_modules/@stryker-mutator/core/schema/stryker-schema.json",
  "testRunner": "vitest",
  "coverageAnalysis": "perTest",
  "mutate": ["src/**/*.ts", "!src/**/*.test.ts"]
}
```
```ts
// abs.ts
export function abs(n: number): number {
  return n < 0 ? -n : n;
}
```
```ts
// abs.test.ts （C0/C1 100% だがアサーションが甘い例）
import { describe, it, expect } from "vitest";
import { abs } from "./abs";

describe("abs (穴あり)", () => {
  it("負も正も通す", () => {
    expect(abs(-3)).toBeGreaterThanOrEqual(0); // 値を固定していない
    expect(abs(3)).toBeGreaterThanOrEqual(0);
  });
});
```
このテストは両分岐を踏むので C1 100% になる。
だが `-n` を `n` に変えるミュータント（abs を恒等関数化する）を入れても、`>= 0` しか見ていないため検出できるかどうかが条件依存になる。
`toBe(3)` で値を固定すれば確実に kill できる。
結果の読み方は次の通り。

- `Killed`：ミュータントを注入したらテストが落ちた。良い（そのコードは守られている）。
- `Survived`：壊したのにテストが通った。テストの穴である。`toBe` 等で値を厳密に固定して塞ぐ。
- `No coverage`：そのコードを実行するテストが無い。まず C0 と C1 を埋める。
- `Timeout` / `Runtime error`：多くは無限ループ化などによる。実害は薄く Killed 相当に扱える。

Mutation Score = Killed / (生成ミュータント − 等価ミュータント)。
これがカバレッジ率より実態に近い、テスト強度の指標である。

### 落とし穴
- 等価ミュータント（注入しても挙動が変わらず、原理的に kill できないもの）が survived に混じる。スコアを 100% に強要しない。
- 全コードに回すと遅い。差分や critical モジュールに限定し、CI では夜間や対象限定で動かす。

### 網羅の定義
- **網羅基準（いつ網羅完了とみなすか）**：これは構造網羅ではなく、テスト強度のメタ基準である。Mutation Score = Killed / (生成ミュータント − 等価ミュータント) を目標値（critical なモジュールでは高め）に達したとき。
- **網羅手順（基準を満たすケース集合の作り方）**：
  1. Stryker でミュータントを生成し、既存テストで Killed / Survived / No coverage を判定する。
  2. Survived には `toBe` 等の厳密アサートを足して値を固定し、kill する。
  3. No coverage はまず C0 と C1 を埋め、再実行してスコアを上げる。
- **達成チェック（漏れの検出）**：Survived がアサーション不足、No coverage がカバレッジ不足の証拠として残っていないこと。等価ミュータントは原理的に kill できないのでスコア 100% を強要しない。計算コストが高いため差分や critical に限定する。

## まとめ: カバレッジの限界とミューテーションの位置づけ

構造カバレッジ（C0 → C1 → 条件 → MC/DC → 経路）は右へ行くほど強いが、いずれもコードのどこを通したかしか測れない。
通すことと、アサートで正しさを確かめることは別である。
アサーションが甘ければ、高カバレッジでもバグは漏れる。

ミューテーションテストは、コードを壊してテストが落ちるかを直接問うことで、通過と検証が一致しない溝を埋める。
カバレッジ率は穴（未到達）を見つける道具、ミューテーションスコアはテストの強さを測る道具として、役割で使い分ける。
どちらも、目標値の達成自体を目的化しない（高カバレッジは良いテストと同義ではない）。

構造網羅（カバレッジ）の各手法は [whitebox-controlflow-basic.md](../whitebox-controlflow-basic/SKILL.md) / [whitebox-controlflow-path.md](../whitebox-controlflow-path/SKILL.md) と [whitebox-dataflow-loop.md](../whitebox-dataflow-loop/SKILL.md) で扱う。
