# hymme

3 つのスキルと、それらが必要とする Nix ツールチェインをまとめた Claude Code プラグインマーケットプレイス。

## 収録スキル

- **loop-engineering**：自然言語の要求を EARS 記法と状態モデルへ構造化し、TLA+(TLC/Apalache)で設計をモデル検査して、反例を Gherkin の受け入れ仕様に落とす。
- **test-design**：テストを設計する、または既存テストをレビューするための手法カタログと選定ワークフロー。テストすべき振る舞いを網羅抽出し、各振る舞いに手法を割り当てる。
- **formal-verification**：雑な仕様を Lean 4 の形式仕様へ落とし込み、証明で検証し(proof-repair ループ)、証明済みの性質を test-first 実装へ橋渡しする。

## インストール(Claude Code)

```
/plugin marketplace add Hakkadaikon/hymme
/plugin install hymme@hymme
```

## ツールチェイン(Nix)

スキルは TLA+(TLC/SANY)、Apalache、make、python3、Lean(elan 経由)を外部コマンドとして呼ぶ。
flake がこれらをまとめて提供する。

一括セットアップ。
`nix` が無ければ先に Determinate Nix を入れる。
システム全体への変更なので実行前に確認を求める(非対話で進めるなら `HYMME_ASSUME_YES=1`)。

```sh
./scripts/bootstrap.sh          # nix develop — ツールチェインを PATH に載せた dev シェル
./scripts/bootstrap.sh install  # nix profile install .#skill-tools — profile に永続化
```

すでに Nix があるなら直接実行してもよい。

```sh
nix develop                       # ツールチェインを PATH に載せた dev シェル
nix profile install .#skill-tools # または profile にインストール
```

これで `tlc` / `sany` / `apalache-mc` / `lake` / `lean` が使えるようになる。
nixpkgs には TLA+ と Apalache の公式パッケージが無いため、flake は固定したリリース成果物を取得して JRE でラップする。
バージョンを上げるときは `flake.nix` の URL とハッシュを揃えて更新する。

次のものは含めていない(必要になったプロジェクトで個別に入れる)。

- Gherkin ランナー：`cucumber-js`(npm)や `godog`(`go install`)。nixpkgs に無い。
- 要求のトレーサビリティ用の `doorstop`：`uv pip install doorstop`。
