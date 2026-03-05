# komorebi-config

Windows タイル型ウィンドウマネージャー [komorebi][komorebi] の設定ファイル一式。

## ファイル構成

| ファイル             | 説明                                                         |
| -------------------- | ------------------------------------------------------------ |
| `komorebi.json`      | komorebi 本体の設定（レイアウト、ボーダー、テーマ、ワークスペース） |
| `komorebi.bar.json`  | ステータスバー (komorebi-bar) の設定（ウィジェット、フォント、テーマ） |
| `whkdrc`             | キーボードショートカットの定義 ([whkd][whkd])                |
| `applications.json`  | アプリごとのウィンドウ管理ルール（.gitignore 対象）          |
| `restart.ps1`        | komorebi / komorebi-bar / whkd を停止・再起動する PowerShell スクリプト |

## セットアップ

### 前提

- [komorebi][komorebi] と [whkd][whkd] がインストール済み
- フォント: JetBrains Mono（komorebi-bar で使用）

### 初回セットアップ

PowerShell で `restart.ps1` を実行する。

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.config\komorebi\restart.ps1"
```

このスクリプトは以下を行う:

1. `KOMOREBI_CONFIG_HOME` / `WHKD_CONFIG_HOME` をユーザーレベル環境変数に永続設定
2. `LowLevelHooksTimeout` レジストリ値を延長（whkd のキーボードフック保護）
3. komorebi, komorebi-bar, whkd を一括起動

### 設定変更後の再起動

```powershell
# PowerShell から直接実行
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.config\komorebi\restart.ps1"

# または whkd ショートカットで個別リロード
# Alt + O         → whkd 再起動（whkdrc の変更を反映）
# Alt + Shift + O → komorebi 設定リロード（komorebi.json の変更を反映）
```

## キーバインド一覧

### 一般

| キー              | 動作                   |
| ----------------- | ---------------------- |
| `Alt + Q`         | ウィンドウを閉じる     |
| `Alt + M`         | ウィンドウを最小化     |
| `Alt + T`         | フロート切替           |
| `Alt + Shift + F` | モノクル切替           |
| `Alt + P`         | komorebi 一時停止切替  |
| `Alt + I`         | ショートカット切替     |

### フォーカス移動

| キー                | 動作                         |
| ------------------- | ---------------------------- |
| `Alt + H / J / K / L` | 左 / 下 / 上 / 右        |
| `Alt + Shift + [ / ]`  | 前 / 次のウィンドウへ循環 |

### ウィンドウ移動

| キー                        | 動作             |
| --------------------------- | ---------------- |
| `Alt + Shift + H / J / K / L` | 左 / 下 / 上 / 右 |
| `Alt + Shift + Enter`       | メインに昇格     |

### スタック

| キー              | 動作                           |
| ----------------- | ------------------------------ |
| `Alt + Arrow Keys` | 方向キーの方向にスタック      |
| `Alt + ;`         | スタック解除                   |
| `Alt + [ / ]`     | スタック内で前 / 次へ          |

### リサイズ

| キー                  | 動作           |
| --------------------- | -------------- |
| `Alt + = / -`         | 横幅 拡大 / 縮小 |
| `Alt + Shift + = / -` | 縦幅 拡大 / 縮小 |

### レイアウト

| キー              | 動作       |
| ----------------- | ---------- |
| `Alt + X`         | 水平反転   |
| `Alt + Y`         | 垂直反転   |
| `Alt + Shift + R` | リタイル   |

### ワークスペース

| キー                | 動作                               |
| ------------------- | ---------------------------------- |
| `Alt + 1-8`         | ワークスペース 1-8 にフォーカス    |
| `Alt + Shift + 1-8` | ウィンドウをワークスペース 1-8 に移動 |

### リロード

| キー              | 動作                   |
| ----------------- | ---------------------- |
| `Alt + O`         | whkd 再起動            |
| `Alt + Shift + O` | komorebi 設定リロード  |

## トラブルシューティング

### whkd がテキストボックスにフォーカスした後に動かなくなる

Windows の低レベルキーボードフック (`WH_KEYBOARD_LL`) がタイムアウトで無効化される問題。`restart.ps1` で以下の対策を適用済み:

- `LowLevelHooksTimeout` レジストリ値を 5000ms に延長
- whkdrc のシェルを `cmd` に変更（PowerShell より起動が高速）

レジストリ変更の反映にはログオフ/再起動が必要な場合がある。

[komorebi]: https://github.com/LGUG2Z/komorebi
[whkd]: https://github.com/LGUG2Z/whkd
