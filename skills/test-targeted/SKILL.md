---
name: test-targeted
description: テストを実行するときの絞り込み規範。pytest / jest / go test / gradle などを回すとき、変更範囲に関係するテストだけを選ぶ手順を参照する。
---

# テスト絞り込み実行ルール

特別な指示がない限り、プロジェクト全体テストの一括実行は行わない。直前の作業内容・最新コミット差分・修正ファイルのパスから影響範囲を特定し、対象テストクラスのみに絞って実行する。

## 実行手順

1. `git log` / `git diff` で修正対象のクラス／パッケージを特定する
2. テストランナーの絞り込みオプションで対象を限定する
   - **Gradle**: `--tests "*ClassNameTest"` または `--tests "FQCN"`
   - **pytest**: `pytest path/to/test_file.py::TestClass::test_func` または `-k "expr"`
   - **jest**: `jest path/to/file.test.ts` または `-t "test name pattern"`
   - **go test**: `go test ./pkg/... -run TestName`
   - **cargo test**: `cargo test --test integration_test test_name`
3. 修正がドメイン層ならドメイン層のテストのみ、インフラ層ならインフラ層のテストのみ実行する

## 例外

以下の場合のみ全範囲テストを実行する：

- ユーザーから「全範囲を走らせて」「全部のテストを通して」等の明示指示があったとき
- 大規模リファクタリング・依存関係変更など影響範囲を絞り込めない作業のとき
- superpowers:subagent-driven-development の implementer 契約に従うとき: 反復中は本スキルどおり絞り込み、**コミット直前の 1 回だけ**全体スイートを回す(契約が要求する 1 回。回した生出力は report の証跡に含める)
- superpowers:finishing-a-development-branch の Step 1(統合前の全体テスト)と、選択肢 1 のマージ後検証

計画書に「全体テスト」と明示されていても、上記の superpowers 契約に当たる回を除き、ユーザーから直接の指示がなければ対象テストに絞る。

## 完了条件

実行コマンドと生出力（終了コード・緑赤の集計行）を応答に提示して完了とする。貼れないなら未完。

## なぜ絞り込むか

- 全範囲テストは実行時間が長く（10分超など）、ローカルリソース起因のノイズ（OOM等）が混入しやすい
- 修正範囲外テストは確認価値が低い
- 失敗時の原因特定も範囲を絞った方が容易
