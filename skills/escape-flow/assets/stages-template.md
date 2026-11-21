# 段の宣言

<!-- tasks/stages.md に置く(git 管理外)。使わない行は消す。
     段は前から spec / unit / integration / e2e / trace / ci の順。
     コマンドは先頭一致で照合される。実行するときは、ここに書いた文字列で始める。
     パスはリポジトリ直下からの glob。 -->

- unit コマンド: `<単体テストを実行するコマンド>`
- unit パス: <単体テストの置き場の glob>
- integration コマンド: `<結合テストを実行するコマンド>`
- integration パス: <結合テストの置き場の glob>
- e2e コマンド: `<e2e テストを実行するコマンド>`
- e2e パス: <e2e テストの置き場の glob>

<!-- 後段(integration 以降)のテストが無いリポジトリは段を宣言できない。`hymme exception request stages` で申請し、作業者の承認を取る。 -->
