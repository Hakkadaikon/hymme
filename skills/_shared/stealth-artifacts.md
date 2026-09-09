# 成果物の置き場と痕跡の規範(裏方で回す)

loop-engineering 系(loopeng-*)・formal-verification・test-design 系(test-*)に共通の規範。
ユーザーが明示しない限り、これらの手法は**裏方**で回す。生成物をリポジトリの git 管理に持ち込まず、手法の痕跡を本体に残さない。

## 作業場所(git 管理外)

| 手法 | 置き場 | 中間生成物 |
| --- | --- | --- |
| loop-engineering 系 | `tasks/loopeng/` | 抽出台帳、EARS/モデル、`.tla`/`.cfg`/`.feature`、トレーサビリティ表、TLC スクラッチ |
| formal-verification | `tasks/fv/` | Lean の `.lean`/`lakefile`、生成 spec |
| test-design 系 | `tasks/test-design/` | T-ID 台帳(`<対象名>.md`。hook が検査する場所なので固定) |
| superpowers(spec / plan) | `docs/superpowers/specs/`、`docs/superpowers/plans/` | **git 管理下**(superpowers の設計でコミットされる)。hymme の成果物置き場ではない。内容には下の「管理番号・手法用語を漏らさない」規範が掛かる |
| superpowers(SDD 作業場) | `.superpowers/sdd/<plan-basename>/` | superpowers 所有の git 管理外領域(`progress.md`・brief・report・review package)。hymme の台帳をここに置かない |
| superpowers(worktree) | `.worktrees/<branch>/`(または EnterWorktree の場所) | 作業ツリーそのもの。中の `tasks/` は worktree ごとに別(下記) |

hymme の3行はいずれも `tasks/todo.md` と同じエリアで作り、`git add` の対象にしない。

### worktree と台帳

superpowers は実装を worktree で行う(superpowers:using-git-worktrees)。`tasks/` は git 管理外なので worktree 間を移動しない。規則: **台帳は作業が起きる worktree の `tasks/` に置く**(hook も cwd 相対で `tasks/` を見る)。brainstorming / writing-plans 段(worktree 作成前)で作った台帳は、SDD の Setup で worktree を作った直後にコントローラが `tasks/` ごと worktree へコピーする(`cp -r`、git 外)。コピーしないと worktree 内に台帳が無く、hook は「台帳なし」として素通りするので implementer への安全網が効かない。ブランチを終えて worktree を消すとき、台帳はマージも移動もしない。トレーサビリティは表に出た結果(テスト名・spec の受け入れ条件)に引き継がれて残る。次の作業で台帳が要れば、その worktree で作り直す。

## git 管理下ドキュメントに手法の存在を書かない(loop-engineering 系 / formal-verification)

README・設計文書・コミットメッセージ・PR に「TLA+ でモデル検査した」「Lean で証明した」等を記載しない。
表に出す成果は通常の実装とテストだけ。
superpowers の spec(`docs/superpowers/specs/`)と plan(`docs/superpowers/plans/`)も git 管理下ドキュメントであり同じ。loop-engineering / formal-verification の成果は「手法名の無い要件・受け入れ条件」として spec に入れ、plan の Task には管理番号なしのテスト名・テストコードとして落とす。
**test-design 系はこの節の対象外**: テストは表に出す成果物そのもので、「境界値テストを追加」等をコミットや PR に書いてよい。test-design 系が従うのは置き場(`tasks/test-design/`)と管理番号(`T-xxx`)を漏らさない規範だけ。

## 管理番号・手法用語を本体に漏らさない

`S-001` 等の抽出 ID、`R-xx` の EARS 番号、TLA+ の `Inv`/disjunct 名、`P7` 等の Lean 番号、`T-001` 等のテスト台帳 ID を、本体ソースコードのコメント・docstring・変数名・テスト名・コミット・ドキュメントに書かない。
`// S-012 を満たす`、`# traceability: R-3`、`test_S001_*` の類は禁止。これらは `tasks/` 配下の台帳の中だけで閉じる識別子で、本体からは存在を意識させない。

表に反映するのは**結果だけ**: 固めた設計を実装に落とし、反例由来の Gherkin や証明済み述語は実装側テストの述語へ移植する。
テストのコメントにも「TLA+ 反例由来」「S-xxx 由来」と書かず、振る舞いそのものを説明する。
本体は「これらの手法を一切知らない人が読んで完結する」状態に保つ。

## 例外(明示オプトイン時のみ)

「spec をリポジトリに入れて」「設計検証を文書化して」「管理番号をコードに残して」「証明をコミット」等とユーザーが言ったときだけ、git 管理下へ置き痕跡を残してよい。

## 環境と裏方は別レイヤ

裏方なのは**生成物**(台帳・spec・feature・証明物)。それを回す**環境側のツール**(tlc/lake/hook/Makefile)はプラグインが配布するもので、検証対象リポジトリの git 管理物ではない。環境に駆動装置があることと、リポジトリに痕跡を残さないことは矛盾しない。
