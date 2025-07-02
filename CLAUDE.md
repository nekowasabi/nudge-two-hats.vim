# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

nudge-two-hats.vim は、Gemini APIを使用してAI駆動のコーディングアドバイスを提供するNeovimプラグインです。コード変更を監視し、通知とバーチャルテキストを通じてコンテキストに応じた提案を提供し、開発者をより良いコーディングプラクティスへと導く「ナッジ理論」を実装しています。

## アーキテクチャ

このプラグインは、関心の分離が明確なモジュラーアーキテクチャに従っています：

### コアコンポーネント

- **`lua/nudge-two-hats/init.lua`**: メインエントリポイントとプラグイン状態管理
- **`lua/nudge-two-hats/config.lua`**: 通知とバーチャルテキストのコンテキスト固有の設定を持つ設定システム
- **`lua/nudge-two-hats/api.lua`**: Gemini API統合とテキスト処理ユーティリティ
- **`lua/nudge-two-hats/buffer.lua`**: バッファ内容の追跡と差分生成
- **`lua/nudge-two-hats/timer.lua`**: 通知とバーチャルテキストコンテキストの両方のタイマー管理
- **`lua/nudge-two-hats/virtual_text.lua`**: バーチャルテキストの表示と管理
- **`lua/nudge-two-hats/autocmd.lua`**: 自動コマンドのセットアップとイベント処理
- **`lua/nudge-two-hats/prompt.lua`**: ペルソナシステムを使用した動的プロンプト生成
- **`lua/nudge-two-hats/message_variety.lua`**: メッセージの多様性とペルソナ選択

### 主要なアーキテクチャパターン

1. **デュアルコンテキストシステム**: プラグインは2つの異なるコンテキストで動作します：
   - **通知コンテキスト**: より長く、実行可能なアドバイスを含む目立つUI通知用
   - **バーチャルテキストコンテキスト**: インラインで表示される控えめで邪魔にならないヒント用

2. **バッファ固有のタイマー管理**: 各バッファは通知とバーチャルテキスト用に別々のタイマーを維持し、バッファ間の干渉を防ぎ、不要なAPI呼び出しを削減します。

3. **ファイルタイプ固有の設定**: 各コンテキスト内でファイルタイプごとに異なるプロンプト、ペルソナ、動作を設定できます。

4. **状態管理**: 中央集権的な状態オブジェクト（`state`）がバッファ内容、タイマー、API呼び出しタイムスタンプ、バーチャルテキスト表示状態を追跡します。

5. **モジュラー関数ラッパー**: `init.lua`は適切な状態参照を維持しながら、専門化されたモジュールに委譲するラッパー関数を提供します。

## 開発コマンド

### テスト
```bash
# plenary test harnessを使用してすべてのテストを実行
nvim --headless -c "lua require('plenary.test_harness').test_directory('test/', {minimal_init = 'luarc.json'})" -c "qa"

# 特定のテストファイルを実行（推奨）
nvim --headless -c "lua require('plenary.test_harness').test_directory('test/api_spec.lua')" -c "qa"
nvim --headless -c "lua require('plenary.test_harness').test_directory('test/timer_spec.lua')" -c "qa"
nvim --headless -c "lua require('plenary.test_harness').test_directory('test/buffer_spec.lua')" -c "qa"
nvim --headless -c "lua require('plenary.test_harness').test_directory('test/autocmd_spec.lua')" -c "qa"
nvim --headless -c "lua require('plenary.test_harness').test_directory('test/virtual_text_spec.lua')" -c "qa"

# 代替: bustedフレームワークを使用して実行（bustedがインストールされている場合）
busted test/
busted test/api_spec.lua
busted test/timer_spec.lua
```

### リンティング
プロジェクトはLua Language Server設定のために`.luarc.json`を使用します：
- グローバル: `vim`がグローバルとして定義されています
- 診断: ヒントは無効化されています

### 手動テスト
プラグインの組み込みコマンドを使用：
```vim
:NudgeTwoHatsStart [filetype1 filetype2 ...]  " モニタリング開始（オプションでファイルタイプ指定）
:NudgeTwoHatsToggle [filetype1 filetype2 ...] " プラグインのオン/オフ切り替え
:NudgeTwoHatsNow            " 即座にアドバイス生成をトリガー
:NudgeTwoHatsDebug          " プラグインの状態とアクティブなタイマーを表示
:NudgeTwoHatsDebugNotify    " デバッグ出力付きで通知を強制実行
```

### 環境セットアップ
- APIアクセスのために`GEMINI_API_KEY`環境変数を設定
- Neovim 0.7.0以上が必要

## 主要な実装詳細

### タイマーアーキテクチャ
- **通知タイマー**: 目立つアドバイスのためのAPI呼び出しをトリガー（デフォルト: 5分）
- **バーチャルテキストタイマー**: インラインテキスト表示を処理（デフォルト: 10分）
- 両方のタイマータイプはバッファ固有で独立して管理されます
- **カーソルアイドル検出**: カーソルが30秒以上動かない場合、すべてのタイマーを一時停止してAPI使用料を節約

### API統合
- Gemini 2.5 Flash Previewモデルを使用
- `GEMINI_API_KEY`環境変数が必要
- API呼び出しを最小限に抑えるためのレート制限とキャッシングをサポート
- 自動言語検出により日本語と英語の両方のコンテンツを処理

### 設定システム
config構造はグローバル設定とコンテキスト固有の設定を分離します：
```lua
{
  -- グローバル設定
  notify_interval_seconds = 300,
  virtual_text_interval_seconds = 600,
  cursor_idle_threshold_seconds = 30,
  
  -- コンテキスト固有の設定
  notification = { /* 通知固有の設定 */ },
  virtual_text = { /* バーチャルテキスト固有の設定 */ }
}
```

### 状態管理
プラグインはいくつかの重要な状態オブジェクトを維持します：
- `buf_content_by_filetype`: バッファとファイルタイプごとのコンテンツ変更を追跡
- `timers.notification` & `timers.virtual_text`: アクティブなタイマーの追跡
- `timers.paused_notification` & `timers.paused_virtual_text`: 一時停止中のタイマーの追跡
- `last_cursor_move_time`: バッファごとの最終カーソル移動時刻
- `virtual_text.extmarks`: バーチャルテキスト表示管理
- `last_api_call_*`: APIレート制限のタイムスタンプ

## 開発ガイドライン

### 新機能の追加
1. 機能が影響するコンテキスト（notification/virtual_text）を特定
2. `lua/nudge-two-hats/`内の関連モジュールを更新
3. `test/`に対応するテストを追加
4. 必要に応じて設定スキーマを更新

### デバッグ
詳細なログを表示するには、設定でデバッグモードを有効にします：
```lua
require("nudge-two-hats").setup({
  debug_mode = true
})
```

### テスト戦略
テストスイートは広範なモッキングを使用してbustedを使用します：
- 分離されたテストのために`vim.*` APIをモック
- UTF-8テキスト処理を特にテスト
- APIサニタイゼーションと言語検出を検証
- タイマーと状態管理をテスト

このプラグインは、パフォーマンス、ユーザー体験、保守性に細心の注意を払った高度なNeovimプラグインアーキテクチャを示しています。