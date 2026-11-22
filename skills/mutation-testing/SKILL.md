---
name: mutation-testing
description: >
  test-catalog の手法カタログの一部。テストの強さを測る(mutation、ミューテーションテスト、
  テストの欠陥検出力、Killed/Survived/No coverage、Mutation Score、Stryker)ことを検証したい
  ときに使う。カバレッジ率が高いのにバグを見逃す原因を調べる、アサーション不足を見つける
  ときに使う。通常は test-catalog スキルの索引経由で手法が選定された後にこのスキルを直接参照する。
disable-model-invocation: true
---

# ミューテーションテスト

カバレッジがコードへの到達を測るのに対し、ミューテーションテストはテスト自身の欠陥検出力を測る。
コードを壊したときにテストが落ちるかを調べ、コードを通しただけで正しさを確かめていない箇所を見つける。

構造網羅（カバレッジ）の各手法は別ファイル（制御フロー系は [whitebox-controlflow-basic.md](../whitebox-controlflow-basic/SKILL.md) / [whitebox-controlflow-path.md](../whitebox-controlflow-path/SKILL.md)、データ・ループ系は [whitebox-dataflow-loop.md](../whitebox-dataflow-loop/SKILL.md)）で扱う。

## 目次

- [ミューテーションテスト（テストの強さを測るメタテスト）](#ミューテーションテストテストの強さを測るメタテスト)
- [まとめ: カバレッジの限界とミューテーションの位置づけ](#まとめ-カバレッジの限界とミューテーションの位置づけ)

## ミューテーションテスト（テストの強さを測るメタテスト）

### 概要
コードに意図的な小さな欠陥（**ミュータント**：`>` を `>=` に、`+` を `-` に、条件の反転など）を注入し、既存テストがそれを失敗として検出（kill）できるかを測る。
テストを試験する側のテストである。

### 目的/いつ使う
カバレッジ率が高いのにバグを見逃す原因を調べるときに使う。

C0 と C1 は行や分岐を通したかしか見ず、通した結果が正しいかをアサートし忘れていても 100% になる。
ミューテーションはコードを壊したらテストが落ちるかを調べるので、通過しているが検証していない箇所を直接検出する。
生き残ったミュータント（survived）は、そのコードを壊してもどのテストも落ちなかった箇所であり、アサーション不足の証拠になる。

注意：計算コストが高い（ミュータント数 × テスト時間）。critical なモジュールに絞って実行する。

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
このテストは両分岐を通すので C1 100% になる。
だが境界の `n < 0` を `n <= 0` に変えるミュータントは、`>= 0` しか見ていないので生き残る(0 を入れるテストも無い)。
`expect(abs(0)).toBe(0)` と `expect(abs(-3)).toBe(3)` で値を固定すれば kill できる。
結果の読み方は次の通り。

- `Killed`：ミュータントを注入したらテストが落ちた。良い（そのコードの欠陥をテストが検出できる）。
- `Survived`：壊したのにテストが通った。テストの抜けである。`toBe` 等で値を厳密に固定する。
- `No coverage`：そのコードを実行するテストが無い。まず C0 と C1 を埋める。
- `Timeout`：多くは無限ループ化による。検出扱いで、Killed と同様に数える。
- `Runtime error` / `Compile error`：無効なミュータント。スコアの計算から除外される。

Mutation Score = (Killed + Timeout) / (有効ミュータント − 等価ミュータント)。Stryker は等価ミュータントを判別しないので、実測値は等価の分だけ低く出る。
これがカバレッジ率より実態に近い、テスト強度の指標である。

### 落とし穴
- 等価ミュータント（注入しても挙動が変わらず、原理的に kill できないもの）が survived に混じる。スコアを 100% に強要しない。
- 全コードで実行すると遅い。差分や critical モジュールに限定し、CI では夜間や対象限定で動かす。

### 網羅の定義
- **網羅基準（いつ網羅完了とみなすか）**：これは構造網羅ではなく、テスト強度のメタ基準である。Mutation Score（上の式）が目標値（critical なモジュールでは高め）に達したとき。
- **網羅手順（基準を満たすケース集合の作り方）**：
  1. Stryker でミュータントを生成し、既存テストで Killed / Survived / No coverage を判定する。
  2. Survived には `toBe` 等の厳密アサートを足して値を固定し、kill する。
  3. No coverage はまず C0 と C1 を埋め、再実行してスコアを上げる。
- **達成チェック（漏れの検出）**：Survived がアサーション不足、No coverage がカバレッジ不足の証拠として残っていないこと(等価ミュータントは除く。スコア 100% を強要しない)。

## まとめ: カバレッジの限界とミューテーションの位置づけ

構造カバレッジ（C0 → C1 → 条件 → MC/DC → 経路）は右へ行くほど強いが、いずれもコードのどこを通したかしか測れない。
通すことと、アサートで正しさを確かめることは別である。
アサーションが弱ければ、高カバレッジでもバグを見逃す。

カバレッジ率は未到達の箇所を見つけるツール、ミューテーションスコアはテストの強さを測るツールとして、役割で使い分ける。
どちらも、目標値の達成自体を目的化しない（高カバレッジは良いテストと同義ではない）。
