# Kasugai（鎹）

macOS（Apple Silicon / macOS 14+）向けのネイティブ AI エージェント操作パネル・ソフトウェアファクトリー基盤。

## 主な特徴

- **ゼロテレメトリ・認証隔離**: アプリ自身は外部通信を行わず、各 CLI プロバイダの認証情報に直接触れません。内蔵プレビューは `WKWebsiteDataStore.nonPersistent()` と厳格な CSP / ルールリストで遮断します。
- **状態遷移の形式検証**: Kizu コア（`std::machine`）および Swift 側状態機械から生成した TLA+ 仕様を TLC で網羅検証します。
- **ソフトウェアファクトリー UI（工場モード）**:
  - 1 発のお題送信後に入力欄を消去する無人実行 UX
  - Blueprint JSON 駆動のワークフロー可視化（`GATE 1` 0 トークン自動検査 → `GATE 2` 隔離レビュー・差し戻しループ・入れ子子工場・稼働時間＆トークン計測）
  - 汎用ランナー同梱（`scripts/factory/`：`meta-factory.mjs` / `factory-optimizer.mjs` / `catalog-server.mjs` / `check-artifact-cdp.mjs`）

## クイックスタート

```sh
just sync     # kugi.toml / kugi.lock から依存ツールを同期
just verify   # fmt / kizu lint / comment lint / check / test / TLA+ drift（時間ゲート 20s）
just ci       # verify + build + 自己テスト（時間ゲート 30s）
just ci-full  # TLC 全状態検証を含むフル検証
just build    # Kizu コア (kasugai.o) + Swift ネイティブビルド + 自己テスト
just install  # Kasugai.app を /Applications/Kasugai.app へ配置
just run      # Kasugai.app をビルドして起動
```

## 工場ランナーの利用例

```sh
# 任意の工場ランナーを環境変数で指定、または Blueprint JSON の runner_script に設定
KASUGAI_FACTORY_RUNNER="$PWD/scripts/factory/meta-factory.mjs" just run
```

## ライセンス

[MIT License](LICENSE)
