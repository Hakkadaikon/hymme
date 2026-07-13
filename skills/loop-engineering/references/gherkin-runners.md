# 生成 `.feature` を実行可能テストにする

`.feature` は受け入れ仕様の**ソース**であって、実装に当てる配線は別レイヤーである。
**まず言語純正の Cucumber 系 OSS を使う**。
これらは「step 定義(glue)を書けば `.feature` がそのまま走る」モデルで、言語ごとに変換スクリプトを書く必要はない。

| 言語 | OSS ランナー | 導入 |
| --- | --- | --- |
| Python | pytest-bdd / behave | `nixpkgs#python3Packages.pytest-bdd`(or behave) |
| Ruby | cucumber-ruby | `nixpkgs#cucumber` |
| JS/TS | cucumber-js | npm(nixpkgs 無し) |
| Go | godog | `go install`(nixpkgs 無し) |
| Rust | cucumber-rs | cargo(外部ランナー不要) |
| Java/Kotlin | cucumber-jvm | maven/gradle |
| .NET | Reqnroll | nuget |

glue の書き方は OSS ごとに違うが、本質は同じで「`When <Action>` を実装の1ステップ呼び出しに、`Then <var> becomes <value>` を post 状態の比較に落とす」だけである。
Python の手本として `bin/gherkin_steps.py` を置いてある(`Given/When/Then` の語彙に対応する pytest-bdd の step。conftest.py で `register_steps()` を呼び、実装を叩く `Model.step` を `model` fixture で渡す)。
他言語でも同じ薄さの glue を1つ書けば足り、それ以上の自作はしない。

## 例外: freestanding / no-libc の C

ここは `.feature` をそのまま走らせる既製 OSS が無い(cucumber-cpp は C++/libc に加え wire 経由で Ruby プロセスが要る。gherkin-c はパーサのみでランナーでない)。
この環境に限り `bin/feature_to_c.py` で機械形式の `.feature` を **C の `CHECK` 列に変換**する。
`When <Action>` をヘルパ呼び出し、`Then <var> becomes <value>` をフィールド比較に落とす。
抽象→具象マッピング(action 名→C 文、TLA 変数→C フィールドと列挙値、ヘッダ)は `--map <map>.json` のプロジェクト設定に隔離し、生成器本体はドメイン非依存(`feature_to_c.py --map <map>.json <Name>.feature`、雛形は `--example`)。
生成 C を自前テストハーネスに 1 TU でリンクして走らせる。

## 配線の生死を緑/赤の両方で実証する

正しい実装で緑、実装をわざと壊して赤が出ることを必ず確認する(出力形式だけ合って実装を見ていない死んだ配線を防ぐ)。
いずれの生成器も**手書きの散文 feature ではなく `trace_to_gherkin.py` 由来の機械形式専用**である。
人が可読性優先で書いた散文 Then は対象外で、従来どおり手で実装テストに落とす。
