# AGENTS.md

- コード（Kizu / Swift / JS / CSS / HTML）にコメントは書かない（`//`・`///`・`/* */`・`<!-- -->` を含む）。意図や不変条件はファイル名・型・命名・lint・テスト・TLA+ で表現し、`just kizu-lint` と `just comment-lint` で機械強制する。
- ドキュメントや ADR は作らない（`docs/` や `TODO.md` の追加も禁止）。意図・不変条件・設計境界は型・命名・lint・テスト・TLA+ で表現する。
- ゼロテレメトリ・認証隔離を破らない。アプリ自身は外部通信ゼロ、`~/.claude` / `~/.codex` 等に直接触れず、`WKWebView` は `kasugai-view:` + `WKWebsiteDataStore.nonPersistent()` + `WKContentRuleList`（失敗時はフェイルクローズ）+ 厳格 CSP + `WKNavigationDelegate` 拒否で遮断し、子プロセス起動時のテレメトリ抑止を既定有効にする。
- 状態遷移は Kizu コア（`std::machine`）と UI 固有最小範囲の Swift（`StateMachineTable`）の双方で純粋遷移関数として書き、`scripts/machine-tla` で生成した素の TLA+（`.tla`）を TLC（`kugi.toml` の `tlaplus` / `tlc`）で全状態網羅検証する（Quint は使わない）。
- UI 文言と設計指針は `DESIGN.md` に準拠する（OS 標準語、会話調・造語禁止、半角英数字と日本語の間は半角スペース、全角`（）`、三点リーダ`…`、モーダルは外側クリック／右上 `×` で閉じる）。
- 依存ツールは `kugi`（`kugi.toml` / `kugi.lock`）、コマンドは `justfile` に集約し、Nix flake や Homebrew は使わない。Kizu コア内スレッド禁止、計画モードは作らない、self-host 中は画面収録系テストを実行しない。
- self-host 中は UI（`Kasugai.app`）と常駐コア（`kasugaid`）が別プロセスで動く。Swift / `view-renderer/` の反映は `just ci && just relaunch`（途中確認は本番隔離の `just dev-relaunch`）で安全に実行できる。Kizu コア（`core/`）変更時の `just daemon-restart` は親デーモンを落とすためエージェントから実行せず、全ターン完了後にユーザーへ案内する。
- 完了前に `just ci`（または `just verify` + `just build`）をすべて通す。TLA+ / TLC 検証は状態遷移・仕様ファイルの変更時に自動実行し、PR マージ前は `just ci-full`（時間上限なし）で強制全検証する。日常のローカル CI は実行時間ゲート（`just verify` 20 秒以内 / `just ci` 30 秒以内）を強制し、超過したら重複排除・アルゴリズム改善で削る。
