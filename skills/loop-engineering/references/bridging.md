# formal-verification(Lean)/ test-design との橋渡し

設計が固まった後、**critical な実装片**(アルゴリズム・セキュリティ性質)は Lean で証明 → `formal-verification` skill / `prover` agent。
TLA+ で「設計が正しい」、Lean で「実装が設計通り」を分担。どちらの成果も Gherkin / property test に落とす。両者を機械的に変換しようとしない(YAGNI)。

反例由来の Gherkin や証明済み述語を、機能レベルのテスト群(正常系・境界・異常系)へ展開する段では `test-design` skill 系を使う。設計の網羅は TLA+ がやるので、`test-design` は残りの機能テストの手法選定(同値分割・境界値・property-based 等)を担う。

**証明済みでも実装が使っているとは限らない(結線チェック)**: Lean の証明は性質の正しさを保証するが、
**その証明対象の関数が実際の呼び出し経路から呼ばれているか**は証明系の関心事の外([`../../loopeng-extract/references/lessons.md`](../../loopeng-extract/references/lessons.md) の
証明と実装の非対称)。証明済み述語を実装へ橋渡ししたら、対応する関数が本番コードパスから呼ばれていることを
grep か呼び出しグラフで確認する。呼ばれていない証明はデッドコードで、緑のまま実効性が無い。
