# hymme 理想形の計画台帳

発行日は 2026-11-21 です。同じ日に、別の担当によるレビューの指摘22件を反映して改訂し、実装の結果を各行に書き込みました。基準は hymme 0.13.1 (923867f) と pstack 0.15.46 です。

残作業の一覧は `tasks/ideal-hymme/remaining.md`、詰まった所の記録は `tasks/ideal-hymme/feedback.md` にあります。

進捗はこの台帳だけで消し込みます。各フェーズの設計書と実装計画には進捗を書かず、この台帳を参照します。

## 凡例

- `[ ]` は未着手、`[~]` は部分完了(残りを同じ行に書く)、`[x]` は完了(実装と検証の証跡が両方ある)です。
- 行末の「機械」は、道具が出した値(終了コード、ハッシュ、差分)で止める項目です。
- 行末の「人」は、作業者の入力を hook が記録し、その記録で止める項目です。
- 行末の「申告」は、作業する本人が書いた記録を読む項目です。強制は書式までにとどまります。
- 印のない行は検査を伴わない作業です。

## 目指す姿

1. 証跡は道具が書きます。検査される本人が合格を書き込む箇所をなくします。
2. 作業者の承認は、作業者の入力から hook が記録します。
3. 検証には鮮度を持たせます。検証が写したコードが変わったら、その検証を失効させます。
4. 後段のテストで見つかった欠陥は、拾えたはずの最も前の段へ戻します。
5. 検査は壊した対象で失敗することを示してから信じます。
6. loop-engineering を使わない通常の作業にも、最小の確認が効くようにします。
7. 検査は hook だけに頼りません。hook が見ない経路でも、道具自身が必要な記録を確かめます。

## 進め方

フェーズ0は調査だけを行います。フェーズ1以降はそれぞれを1つの project として brainstorming、設計書、test-design、実装計画、実装の順に進めます。

フェーズの順は次のとおりです。フェーズ1はほかのすべての前提です。フェーズ2はフェーズ1のあとに行います。フェーズ3はフェーズ2で作る承認の方法を使うので、フェーズ2のあとに行います。フェーズ4はフェーズ3の欠陥の記録を使います。フェーズ5はフェーズ1のあとならいつでも始められます。フェーズ6は最後に行います。

どのフェーズも次の3つがそろってから完了とします。

- 足した検査に、通す例と止める例のテストがあり、flake の checks と README の一覧に登録されている。
- 足した検査が過去に実際に起きた失敗か、それを再現した入力で止まることを示している。
- そのフェーズの変更で食い違う既存のスキル、reviewer の検査項目、テストを同じフェーズで直している。

## 先に決めること

作業者だけが決められる判断です。決まるまで、括弧内の仮の方針で計画を書いています。

- [x] D-1 superpowers への依存を残すか。フェーズ1の前に決める(仮: 残す。残さない場合は、superpowers を参照する41ファイルの書き直しをフェーズ6に加える) → 決定: 残す(仮の方針のまま)。作業者が /goal で自律の実行を指示したため、仮の方針で進めた
- [x] D-2 通常の作業にどこまで効かせるか。フェーズ3の前に決める(仮: 完了の検証と、後段の欠陥を前段へ戻す流れの2つだけ) → 決定: 仮の方針のまま。hymme の台帳を持たないリポジトリには、レビューの記録と欠陥の記録だけを求める(checks.py の managed)
- [x] D-3 誤って止まる回数が増えることをどこまで許すか。フェーズ1の前に決める(仮: 作業者が承認した期限つきの例外で通す) → 決定: 仮の方針のまま。例外は作業者の承認つき、最長90日(hook.py の MAX_EXCEPTION_DAYS)
- [x] D-4 状態図に pstack の statechart を使うか、hymme で作るか。フェーズ2の前に決める(仮: 0-07 の結果で決める) → 決定: hymme で作る(tasks/ideal-hymme/phase0.md の 0-07。loopeng/lib/hymme/chart.py)
- [x] D-5 SMT 経路で実物をどう確かめるか。フェーズ4の前に決める(仮: 実関数とモデルの出力を突き合わせるテスト) → 決定: 仮の方針のまま。検証容易性の台帳の「突き合わせ:」の行のコマンドを記録する

## フェーズ0 事前の確かめ

hook の仕様と、hymme と pstack の未読部分を確かめます。結果は各行に書き、後続フェーズの設計に使います。

- [~] 0-01 AskUserQuestion の回答を PostToolUse の hook が受け取れるか試す → 未実験。`-p` では AskUserQuestion が使えない。承認は 0-02 の方法にしたので、この確かめは不要になった(tasks/ideal-hymme/phase0.md)
- [x] 0-02 UserPromptSubmit の hook で作業者の承認の語を記録できるか試す(0-01 が使えないときの代わり) → tasks/ideal-hymme/phase0.md。実際のセッションで承認が記録されることも確認(scratchpad の e2e-repo、記録は approval claims Counter)
- [x] 0-03 レビュー担当のサブエージェントの判定を hook 側で記録できるか試す → tasks/ideal-hymme/phase0.md(SubagentStop に agent_type と last_assistant_message)
- [~] 0-04 記録ファイルへの本人の書き込みを止められるか試す。Write、Edit、NotebookEdit、Bash、シェルを実行できる MCP の道具の5経路を対象にする → tasks/ideal-hymme/phase0.md。Write は実験、MCP と NotebookEdit は文書の確認だけ。残り: MCP の道具での実験
- [x] 0-05 Bash の終了コードを PostToolUse の hook が読めるか試す → tasks/ideal-hymme/phase0.md(PostToolUseFailure の error が `Exit code N`)
- [x] 0-06 0-03、0-04、0-05 のそれぞれについて、使えなかったときの代わりの方法を決める。候補は、hymme が配る実行用のスクリプトが終了コードを記録する方法、書き込みを止める代わりに作業ツリーの外の保存とハッシュで改ざんを見つける方法、判定用のスクリプトがレビューの結果を記録する方法 → tasks/ideal-hymme/phase0.md の「0-06 代わりの方法」
- [x] 0-07 pstack の statechart のスクリプト一式を取得し、`example-counter.md` の spec で動かして報告の形を確かめる(取得済みなのは markdown だけ) → tasks/ideal-hymme/phase0.md の「0-07 状態図」。pstack 版が Counter で動くことを確認し、hymme で作ると決めた
- [~] 0-08 サブエージェントと、別の worktree での作業に、hook と `tasks/` の記録がどう見えるか試す → tasks/ideal-hymme/phase0.md。記録が worktree をまたぐことはテストで確認(loopeng/lib/tests/test_hymme.py の test_records_are_shared_with_a_second_worktree)。残り: サブエージェントの中の hook の発火は文書の確認だけ
- [x] 0-09 `loop-*` と `trace_check.py` と `smt_oracle.py` が失敗をファイルに残しているか調べる → tasks/ideal-hymme/existing-survey.md の B(記録は残していない)
- [x] 0-10 loopeng-modelcheck の references、formal-verification、test-extract、nonfunctional-perf、levels-operational を通読し、この台帳の「今は無い」の判定を見直す → tasks/ideal-hymme/existing-survey.md の A(無い 38、一部在る 45、既に在る 2)
- [x] 0-11 pstack の全スキルと全 playbook について、取り込む、取り込まない、既に在る、の採否の表を作る。未読の playbook 8本と原則の残りもここで読む → tasks/ideal-hymme/pstack-adoption.md(取り込む 27、既に在る 8、取り込まない 46)
- [x] 0-12 hook 1本あたりの実行時間を測り、本数を増やせる上限を決める → tasks/ideal-hymme/phase0.md の「0-12」。新しい入口は1事象につき Python の起動1回
- [x] 0-13 pstack の文面や script を取り込む箇所に、MIT ライセンスの表示を付ける方法を決める → README.md の「謝辞」。文面とスクリプトは取り込まず、考え方の出どころを書いた

## フェーズ1 証跡の記録

本人の申告を、道具が書く記録へ置き換えます。pstack の「同期コミット」と patch-id の考え方をここに入れます。

- [x] 1-01 今ある検査のうちテストの無い3つ(pr-review-gate、git-guard、loopeng-extract-gate)に、通す例と止める例のテストを足す → scripts/git-guard.test.sh(18例)。pr-review-gate と loopeng-extract-gate は新しい入口に置き換え、その検査は IntegrationTest と ClaimsGateTest が持つ
- [x] 1-02 CI を用意し、ローカルと同じ checks を回す → .github/workflows/check.yml。main への push で実行され、成功した(run 44886、コミット 56cc7b4)。1回目と2回目は、上流が差し替えた TLA+ の jar のハッシュ不一致で落ち、公開のダイジェストと照合して直した
- [~] 1-03 コマンドの解析を1つにまとめる。`cd` のあとに連結した呼び出し、`SPEC=` の無い呼び出し、`tlc` と `apalache-mc` と `lean` の直接の実行を、検証の入口として見つける 機械 → loopeng/lib/hymme/cmdparse.py を新しい入口と verifiability-gate.sh が共有。直接の実行も入口として見つける(ParseTest)。残り: loopeng-lint-gate.sh と git_guard.py は自前の解析のまま
- [~] 1-04 解析できない入力、道具が無い環境、作業者と対話できない実行のそれぞれで、止めるか通すかを1つの表に定義し、全検査をそれに合わせる 機械 → 新しい入口は、鍵が無いと検証の入口と統合の入口を止め、ほかは通す(test_without_a_key_…)。壊れた入力は通す。残り: 既存の3本の sh は元の方針のままで、1つの表にはしていない
- [x] 1-05 証跡の共通の形を1か所で定義する(コマンド、終了コード、コミット、patch-id、対象ファイルのハッシュ、書いた道具のバージョン) → loopeng/lib/hymme/store.py の append(kind、ts、version、変更の ID、署名)。入力のハッシュは hook.py の input_hashes
- [x] 1-06 証跡、承認、欠陥の記録の置き場を決める。別の worktree やサブエージェントからも同じ記録が読める場所にし、`stealth-artifacts.md` の表と ledger-flow を直す → 記録は git の共通ディレクトリの hymme/(store.root)。skills/_shared/stealth-artifacts.md の「hook の記録」節
- [x] 1-07 `loop-*`、`smt_oracle.py`、`trace_check.py`、`verifiability.py` が、実行のたびに 1-05 の形で記録を書く 機械 → 方法を変更: 道具は書かず、hook が PostToolUse と PostToolUseFailure で記録する(hook.py の post_tool、ReviewAndPremiseTest と ManagedRepoTest)
- [x] 1-09 diff-review の証跡をスクリプトが書く形に改める。must の件数は、レビュー担当の報告からスクリプトが数える 機械 → 方法を変更: reviewer の最後の3行を hook が記録する(IntegrationTest)。skills/diff-review/SKILL.md の「4. 判定の記録」
- [x] 1-10 レビュー合格の `[x]` を、0-03 か 0-06 の方法による記録に置き換える。2本の `reviewer.md`、`check-reviewer-checklist.sh`、`verifiability.test.sh`、verifiability の台帳のひな形を合わせて直す 機械 → hook.py の subagent_stop と checks.py の review(test_verifiability_review_is_a_record_tied_to_the_ledger_and_the_code)。ひな形、reviewer.md、verifiability-gate.sh を直した(db4139b、b7f5da1)
- [x] 1-11 証跡のファイルへの本人の書き込みを、0-04 か 0-06 の方法で止めるか見つける 機械 → checks.py の protected(ProtectedTest)。署名の合わない行は読まない(StoreTest)。限界は design.md の「限界」
- [x] 1-12 例外の決まりを作る。例外には理由、期限、作業者の承認を必須にし、期限を過ぎた例外を止める。「人」の印の検査は例外で通せないようにする 人 → checks.py の EXEMPTABLE と Ctx.exempt、hook.py の user_prompt(test_exception_rules)。作業者の確認は表に無いので外せない
- [x] 1-13 PR 作成時の検査を、コミットの一致から patch-id の一致へ改める(rebase だけでは失効しない)。pr-create スキルを合わせて直す 機械 → store.change_id(test_change_id_survives_a_rebase_and_changes_with_the_code)。skills/pr-create/SKILL.md
- [x] 1-14 PR 作成時と同じ検査を、`glab mr create`、API 経由の PR 作成、ローカルでの merge、PR を作ったあとの push にも掛ける 機械 → hook.py の leaves と PR_TOOL(test_every_way_out_is_stopped_without_a_review、test_push_after_the_pr_and_local_merge_are_checked_too)。限界: Web の画面で作る PR は見えない
- [x] 1-15 verifiability の台帳にある `path::関数` と差分を突き合わせ、対象が変わっていたら再検査を求める 機械 → checks.py の stale_names と integration(test_stale_verification_and_missing_surface_run_stop_it)
- [x] 1-16 ブランチの差分が触れる spec の名前を、1-15 の対象の一覧から出すコマンドを作る 機械 → `hymme specs`(test_specs_command_lists_what_the_change_touches)
- [x] 1-17 対象が変わったときの再検査の手順を書く。変更を「影響なし」「記述がコードと合わなくなった」「約束を意図して変えた」「約束が破れたおそれ」の4つに分ける 申告 → skills/verifiability/SKILL.md の「対象のコードが変わったとき」
- [x] 1-18 「約束を意図して変えた」と分けるときは、根拠(テスト、変更履歴、コミットの説明)の引用を必須にする 申告 → 同上と skills/verifiability/reviewer.md の「対象の変更の分類」
- [x] 1-19 新しい hook の事象を `hooks.json` に登録し、新しいスクリプトを flake の配布の一覧と `loopeng-tools.test.sh` に加える → hooks/hooks.json、flake.nix(loopengTools に hymme と lib、checks に hymme-core と git-guard)。nix flake check が exit 0
- [~] 1-20 古い形式の証跡(今の `evidence.md`、手書きの合格の行、承認の無い進行中の `tasks/loopeng`)を読んだら、作り直しを求めて止める 機械 → 古い形式の証跡と手書きの合格の行は、もう読まない。記録が無いので、新しい手順を示す文言で止まる。残り: 古い形式を見つけて知らせる専用の文言は無い
- [x] 1-21 hook と道具のバージョンが食い違うときに、それを知らせて止める 機械 → 申請に道具のバージョンを入れ、hook が比べる(test_request_from_a_tool_of_another_version_is_refused、test_the_library_and_the_plugin_carry_one_version)

## フェーズ2 作業者の確認

EARS にした要件について、形式検証で何を実証するかを、検証の前に必ず作業者へ確かめます。

- [x] 2-01 確認用の一覧の形を決める。EARS の1行ごとに「示すこと」「示さないこと」「破れたときの害」を平文で1文ずつ書く → ledgers.py の claims_problems、skills/loopeng-formalize/assets/claims-template.md
- [x] 2-02 一覧に、有限にした値の範囲と、モデルから捨てた領域を載せる → 同上(「有限にした範囲」「扱わない領域」が空だと形の検査で落ちる)
- [x] 2-03 一覧には手法の用語と管理番号を書かない(作業者が検証の言語を知らなくても判断できる形にする) → ledgers.py の METHOD_WORDS(test_claims_list_with_an_empty_cell_a_missing_section_and_a_method_word)
- [x] 2-04 loopeng-formalize の EARS を書いた直後に、2-01 の一覧を作る手順を入れる → skills/loopeng-formalize/SKILL.md の「作業者の確認」。位置は「EARS とモデルを決めた直後、spec を書く前」に変えた(有限にした範囲がモデルで決まるため)
- [x] 2-05 作業者に見せる文面を、スクリプトが一覧のファイルからそのまま出す(作業する本人が要約や別の質問に差し替えられないようにする) 機械 → hook.py の hymme_results が、ファイルの中身を systemMessage で作業者に出す(test_the_worker_sees_the_list_itself)
- [x] 2-06 どの一覧が承認待ちかの状態を記録し、承認の入力がどの一覧に対するものかを取り違えないようにする 機械 → 申請は符号ごとのファイル。表示する申請はコマンドの引数から決める(hook.py の requested_code、test_the_chart_must_match_…)
- [x] 2-07 作業者の承認を 0-01 か 0-02 の方法で hook が記録する。記録には一覧のハッシュを含める 人 → hook.py の user_prompt(ClaimsGateTest)。実際のセッションでも確認
- [x] 2-08 承認の記録が無いか、一覧が承認後に変わっていたら、1-03 で見つけた検証の入口をすべて止める 人 → checks.py の claims(test_passes_after_the_worker_approves_and_stops_again_when_the_list_changes)
- [x] 2-10 SMT 経路と Lean の性質の一覧にも、同じ確認と同じ検査を入れる 人 → 一覧は tasks/loopeng と tasks/fv の両方で探す(test_proof_work_under_tasks_fv_needs_the_list_but_no_extraction_ledger)。SMT は同じ入口の検査
- [x] 2-11 作業者と対話できない実行(サブエージェント、無人の実行)では承認を取らずに止める。modeler と prover は BLOCKED で返す。`parallel-delegation.md` を合わせて直す → agents/modeler.md、agents/prover.md、skills/_shared/parallel-delegation.md。hook の文言にも BLOCKED で返す指示がある
- [x] 2-12 D-4 の結論に沿って、状態図を作る道具を用意する。pstack のものを使うなら実行環境を flake に加え、hymme で作るなら実装する → loopeng/lib/hymme/chart.py と `hymme chart draw`(ChartRunTest、実際の TLC で実行)
- [x] 2-13 モデル検査のあとに2回目の確認を置く。状態図と、違反に至る最短の経路と、文面の往復確認の結果を作業者へ示す 人 → `hymme chart request` と checks.py の chart_problem。文面は skills/loopeng-modelcheck/SKILL.md の手順4
- [x] 2-14 状態図が今の spec から作られたこと(ハッシュの一致)と、検査されなかった規則が0件であることを検査する 機械 → checks.py の chart_problem(test_the_chart_must_match_the_spec_leave_nothing_open_and_be_approved)
- [x] 2-15 作業者が項目を直したときの手順を書く。EARS、モデル、一覧の順に作り直し、2-07 の承認を取り直す → skills/loopeng-formalize/SKILL.md の「作業者の確認」(直すときの順)
- [x] 2-16 verification-reviewer の検査項目に、承認の記録と一覧の対応を加える → agents/verification-reviewer.md、skills/loop-engineering/reviewer.md の「確認の一覧と承認」

## フェーズ3 後段の欠陥を前段へ戻す

結合テストや e2e で見つかった問題を、単体テストなどの前の段で拾えるようにします。拾えるようになるまで先へ進めません。

- [x] 3-01 段の順を定義する。前から、要件とモデル、単体と性質のテスト、結合、e2e、実ログの突き合わせ、CI と本番の順とする → ledgers.py の STAGES(spec、unit、integration、e2e、trace、ci)
- [x] 3-02 リポジトリごとに、どのコマンドとどのパスがどの段かを宣言する場所を決める → tasks/stages.md(ledgers.py の stages、skills/escape-flow/assets/stages-template.md)
- [x] 3-03 宣言が無いリポジトリでは、1-14 の入口で宣言を求めて止める(D-2 の結論に沿う) 機械 → checks.py の integration(test_missing_declarations_stop_it_…)。hymme の台帳を持つリポジトリだけ。段を宣言できないリポジトリは作業者の承認つきの例外
- [x] 3-04 後段のテストが失敗したら、0-05 か 0-06 の方法で欠陥の記録を自動で開く 機械 → hook.py の open_escape(test_a_failing_later_stage_opens_a_record_that_holds_the_change)
- [~] 3-05 欠陥の記録を開くのは、基準のブランチでは通っていたテストが失敗したときに限る(先に書いた、まだ通らないテストでは開かない) 機械 → 近似で実装: その段のテストをこのブランチで変更しているあいだは開かない(test_a_unit_failure_or_a_stage_under_construction_opens_nothing)。残り: 基準のブランチでの合否は見ていないので、後段のテストを足しているブランチでは既存のテストの退行で自動では開かない
- [~] 3-06 `trace_check.py` の不一致も同じ記録に入るようにする 機械 → 実ログの不一致は実行の記録に残り、通るログが揃うまで統合の入口で止まる。残り: 欠陥の記録は自動では開かない(作業中の不一致は設計の往復で普通に起きるため)。実装の穴と判定したら手で開く、と skills/escape-flow に書いた
- [~] 3-07 CI の失敗は実行の結果を取り込むコマンドで記録を開く。gh-ci-investigate を合わせて直す 機械 → tasks/stages.md に `ci コマンド:` を宣言すると、その失敗で記録が開く(ひな形に例を書いた)。skills/gh-ci-investigate/SKILL.md の手順5 は手で開く。残り: 宣言した場合の動作は unit の例だけで、実際の CI では未確認
- [x] 3-08 作業者から報告されたバグと本番の欠陥は、本人が記録を開く 申告 → `hymme escape open`(test_open_by_hand_list_and_stats)
- [x] 3-09 欠陥の記録の形を決める。症状、見つかった段、拾えたはずの最も前の段、抜けた理由、前段に足したテストの名前を書く → ledgers.py の ESCAPE_FIELDS、skills/escape-flow/assets/escape-template.md
- [x] 3-10 抜けた理由の分類を決める。要件の抜け、モデルで捨てた領域、手法の選び違い、テストの書き漏れ、検証の弱いテスト、前段では原理的に拾えない、の6つとする → ledgers.py の ESCAPE_CAUSES。review-feedback の4分類との関係は skills/review-feedback/SKILL.md に書いた
- [x] 3-11 前段に足したテストが、修正前のコミットで失敗し、修正後に通ることをスクリプトが実行して記録する 機械 → cli.py の red_then_green(test_closing_needs_a_test_in_an_earlier_stage_that_was_red_before_the_fix)。限界: 修正前に落ちた理由は見ない
- [x] 3-12 足したテストのパスが、3-02 の宣言で、見つかった段より前の段に当たることを検査する 機械 → ledgers.py の escape_problems(同じテスト、test_escape_record_fields_are_validated)
- [x] 3-13 抜けた理由が要件かモデルにあるときは、loopeng-extract か loopeng-formalize へ戻す。承認済みの一覧が変わり、2-07 の承認を取り直したことを、閉じる条件にする 人 → hook.py の hymme_results(test_a_requirement_gap_closes_only_after_the_list_is_approved_again)
- [x] 3-14 開いたままの欠陥の記録があるあいだ、1-14 の入口をすべて止める 機械 → checks.py の integration(escape_open。例外で外せない)
- [x] 3-15 ブランチに `fix` 型のコミットがあるのに欠陥の記録が無いとき、1-14 の入口を止める(種別は本人が付けるので、3-04 を主、これを補助とする) 申告 → checks.py の integration(test_fix_commit_needs_an_escape_record、test_a_fix_commit_is_covered_by_a_record_opened_on_this_branch_even_after_more_commits)
- [x] 3-16 「前段では原理的に拾えない」で閉じるときは、理由と 2-07 の方法による作業者の承認を必須にする 人 → `hymme escape unreachable` と承認(test_unreachable_needs_the_worker)
- [x] 3-17 同じ種類の抜けをほかの箇所から探した結果(見つけた箇所か「該当なし」)を、欠陥の記録の必須の欄にする。手順は review-feedback の水平展開を使う 申告 → 「水平展開」は必須の欄(ledgers.py の ESCAPE_FIELDS)。手順は skills/escape-flow/SKILL.md
- [x] 3-18 足したテストを test-design の台帳に新しい行として加える 申告 → skills/test-verify/SKILL.md と skills/escape-flow/SKILL.md(既存の規則につないだ)
- [x] 3-19 欠陥の記録を読み、抜けた理由の分類ごとの件数を出すスクリプトを作る。同じ分類が2回出たら 5-10 の対象にする 機械 → `hymme escape stats`(test_open_by_hand_list_and_stats)。skills/review-feedback/SKILL.md の 3.5

## フェーズ4 バグ修正と完了の検証

実物で再現し、実物で確かめる流れを作ります。pstack の bug-fix、Prove It Works、create-verification-skill を参考にします。

- [x] 4-01 バグ報告からの入口を書く。spec がある領域は実ログを採って `trace_check.py` にかけ、無い領域は再現コマンドを使う → skills/escape-flow/SKILL.md(バグ報告からの入口)
- [x] 4-02 再現コマンドが修正前のコミットで失敗し、修正後に同じコマンドが通ることを、スクリプトが実行して記録する。別の面で確かめた結果は合格にしない 機械 → cli.py の escape verify の「再現のコマンド」(test_the_reproduction_must_fail_before_the_fix_and_pass_after)
- [x] 4-03 失敗する再現を、修正より前のコミットに置く。commit-flow と micro-commit を合わせて直す 申告 → 方法を変更: コミットの順は求めない。修正前のコードを一時の worktree に取り出し、足したテストだけを重ねて実行する(micro-commit の規則と衝突しないようにした)
- [x] 4-04 リポジトリごとに、実システムの動かし方を定義する形を決める(起動、健全性の確認、操作、証跡の採取、後片付け) → tasks/surface.md(ledgers.py の surface、skills/real-surface/assets/surface-template.md)
- [x] 4-05 リポジトリを調べて 4-04 の定義を作り、機能を1つ動かして定義が使えることを示す手順を書く → skills/real-surface/SKILL.md
- [x] 4-06 4-04 の定義がコードの変更に追いついているかを確かめ直す手順を書く → skills/real-surface/SKILL.md(定義を確かめ直す手順)
- [x] 4-07 4-04 の定義が無いリポジトリでは、1-14 の入口で定義を求めて止める(D-2 の結論に沿う) 機械 → checks.py の integration(no_surface、surface_invalid)。hymme の台帳を持つリポジトリだけ
- [x] 4-08 ログを採るスクリプトが、ログのハッシュと起動コマンドを記録する 機械 → `hymme capture` と hook の capture の記録
- [x] 4-09 `trace_check.py` に渡されたログが 4-08 の記録と一致するかを検査する 機械 → checks.py の integration(log_not_captured。test_real_logs_are_required_for_a_spec_and_the_broken_one_must_fail)
- [x] 4-10 TLA+ 経路を通った作業では、正常系、高負荷、障害注入のログが通ることを 1-14 の入口で求める 機械 → 同じテスト
- [x] 4-11 わざと壊した実装のログが `trace_check.py` で不一致になることを、出口の条件に加える 機械 → 同じテスト(壊したログは終了コード 1 だけを認める)
- [~] 4-12 verifiability の切り出しの前後で、同じ固定テストが通ることを台帳に記録する。通常のリファクタリングにも先に振る舞いを固定する同じ手順を当てる 機械 → skills/verifiability のひな形に、切り出し前後のコマンドの欄を置いた。残り: 機械の検査は無い(reviewer が見る)。通常のリファクタリングへの適用は skills/diff-review/references/design.md の観点まで
- [x] 4-13 D-5 の結論に沿って SMT 経路の実物での確かめを作る。実関数とモデルの出力が食い違う入力が0件であることを、スクリプトの終了コードで示す 機械 → ledgers.py の parity_commands と checks.py(test_a_model_of_a_pure_decision_needs_the_real_function_compared)
- [x] 4-14 通常の作業でも、4-04 の定義で実物を動かした証跡が今の patch-id に対して在ることを、1-14 の入口で求める(D-2 の結論に沿う) 機械 → checks.py の integration(surface_not_run。test_a_failed_or_inconclusive_run_is_not_a_pass)。hymme の台帳を持つリポジトリだけ
- [x] 4-15 道具が失敗した規則の名前を記録に残すようにする 機械 → 方法を変更: 道具の出力から hook が規則の名前を読む(hook.py の RULES)。名前は記録にだけ残り、本体には出ない
- [x] 4-16 修正を挟んでも同じ規則で2回続けて落ちたら、前提とその確かめ方の記録が無い限り、3回目の実行を止める 機械 → checks.py の premise(test_third_run_after_two_failures_on_one_rule_needs_the_premise)
- [x] 4-17 検証と本番で値が違いうる定数(容量、タイムアウトなど)の一覧を、完了前の台帳の必須の欄にする 申告 → tasks/surface.md の「検証と本番で違う値」が必須(ledgers.py の surface)

## フェーズ5 レビューと設計原則

レビューの指摘に確かさの段階を持たせ、pstack の原則のうち判断を要するものをレンズに入れます。

- [x] 5-01 conformance レンズの指摘と「全経路で守られる」という主張に、確かさの段階を付ける。段階は主張のみ、行を示した、机上でたどった、実行した、実物で再現した、の5つとする 申告 → skills/diff-review/SKILL.md、references/conformance.md(既存の区分との対応表)
- [x] 5-02 指摘を実行で確かめられるレビュー担当を用意する。今の diff-reviewer は読み取り専用の許可リストに縛られているので、隔離した作業ツリーで実行できる担当か、許可リストの改定を設計する → skills/diff-review/scripts/run-in-copy.sh と許可リスト(scripts/collect-diff.test.sh に通す例と止める例)
- [x] 5-04 段階が「主張のみ」の must 指摘と主張が0件であることを、1-14 の入口で検査する 申告 → checks.py の integration(claim_only。test_must_or_unproven_claims_stop_it_per_lens_set)
- [x] 5-05 変更が安全だと言える根拠の事実を1つ書き、実行で確かめる手順をレンズに入れる(pstack の blast-radius) → skills/diff-review/references/design.md(安全の根拠を1つ書いて確かめる)
- [x] 5-06 design レンズに6つの観点を加える。先に削る、読み手の負荷を減らす、境界で検証する、領域をデータ構造に写す、型で不正な状態を防ぐ、起きてはならない状態を隠すだけの修正を通さない → skills/diff-review/references/design.md
- [x] 5-07 loopeng-extract の「閉じる前のチェック」に、2回実行したとき、途中で止まったあと、複数の書き手が同じ対象に書くとき、の3行を加える → skills/loopeng-extract/assets/extract-template.md
- [x] 5-08 `loopeng-extract-gate.sh` が「閉じる前のチェック」の節まで検査するようにする 機械 → 方法を変更: 古い sh は消し、新しい入口が「閉じる前のチェック」まで読む(ledgers.py の extract_problems、test_extract_ledger_closed_and_open)
- [x] 5-09 規則と、それを強制する手段の対応表を README に置く。強制する手段の無い規則が一覧で見えるようにする → README.md の「強制のしくみ」の表
- [x] 5-10 3-19 で同じ分類が2回出た抜けと、強制の無いまま2回破られた規則について、構造で防ぐ手段(型、lint、検査)を作る手順を review-feedback に加える → skills/review-feedback/SKILL.md の 3.5(既存の「1回目で埋め込む」は変えていない)
- [x] 5-11 PR の本文に、影響の範囲と検証の結果の欄を必須にする。pr-create のひな形を直す 申告 → checks.py の pr_body と skills/pr-create/SKILL.md。英語の見出しも認め、PR のテンプレートがあるリポジトリでは見ない
- [x] 5-12 nonfunctional-perf に、pstack の benchmark-checklist の7つの問いを加える → skills/nonfunctional-perf/SKILL.md の「数値を報告する前の7つの問い」

## フェーズ6 統合

- [x] 6-01 using-hymme の地図、`session-start.sh`、`session-start.test.sh` を、新しい流れに合わせて書き直す → skills/using-hymme/SKILL.md の「強制のしくみ」。session-start.sh は変更不要で、テストは通る
- [x] 6-02 hook の実行時間を測り、0-12 の上限に収まっていることを確かめる → 通常の呼び出しで約110ミリ秒、統合の入口で約1秒(scratchpad の timing.py で計測)
- [x] 6-03 すべての検査のテストが flake の checks と README の一覧に載っているかを点検する → nix flake check が 13 種で exit 0。README の一覧に hymme-core と git-guard を追加
- [ ] 6-04 Counter の例で、0段から PR 作成までを全検査つきで通す
- [~] 6-05 loop-engineering を使わない通常の作業で、e2e の失敗から、単体テストの追加、PR 作成までを全検査つきで通す → 最小アプリで、作業者のバグ報告から、欠陥の記録を開く、実物で再現、単体テストの追加、`hymme escape verify`、記録を閉じる、までを実際のセッションで通した(記録 E20261121-185223、アプリ側のコミット 86aac34)。残り: 統合(main への merge)まで通していない。e2e の失敗から自動で記録が開く経路は、実際のセッションでは動かしていない
- [ ] 6-06 hymme 自身の開発に1か月適用し、誤って止まった回数を検査ごとに数える。同じ検査が3回以上誤って止めたら、その条件を見直す
- [x] 6-07 README、各スキルの「強制のしくみ」、`plugin.json` と `marketplace.json` の説明を更新し、バージョンを上げる → 3fda6af(README、plugin.json 0.14.0、marketplace.json)

## 対象外

- 人を待たずに進める方針と、PR を下書きにしない方針は入れません。hymme の承認と検査の考え方と逆だからです。D-3 の結論が変われば見直します。
- 役割ごとのモデルの割り当て、swarm、複数ベンダーでの arena は入れません。Claude Code では他社のモデルを使えないからです。使えるようになれば見直します。
- babysit、shipping の自動マージ、recall、unslop、comment-sicko は入れません。検証の流れの外にあるからです。
- eval の目隠しの手順は入れません。hymme のスキルを比較評価する作業を始めるときに登録し直します。
- hillclimb は入れません。性能を継続して改善する作業を扱うときに登録し直します。
- ここに無い pstack の要素の採否は 0-11 で決めます。取り込まないと決めたものは、理由を付けてこの節に加えます。
- 1-08 道具が動く前に必要な記録を自分で確かめる。hook が見ない実行(スクリプトや Makefile の中)は記録されず、統合の入口で「記録が無い」として止まるので、道具の側の検査は足していません。道具は署名の鍵を読めないので、確かめられるのは署名の無い記録までです。hook が見ない経路で検証が黙って通る事例が出たら登録し直します。
- 2-09 道具自身の確かめに承認の記録を加える。1-08 を入れていないので、これも入れていません。再登録の条件は 1-08 と同じです。
- 5-03 指摘に付いたコマンドを別のスクリプトが再実行する。レビュー担当が写しの中で自分で実行する形(5-02)にしたので、要らなくなりました。レビュー担当の実行の結果が信用できない事例が出たら登録し直します。

## 未確認のまま書いた前提

- hook が AskUserQuestion の回答、Bash の終了コード、サブエージェントの判定を受け取れることは未確認です。フェーズ0で確かめ、使えなければ 0-06 で決めた代わりの方法を使います。
- シェルを実行できる MCP の道具に hook の検査が効くかは未確認です。効かない場合に備えて 1-08 を置いています。
- hymme に今は無いと判定した機能は grep の結果に基づきます。0-10 で見直します。
- pstack の内容は 2026-11-21 に取得したバージョンに基づきます。
