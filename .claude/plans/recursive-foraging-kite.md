# Focus window の border が水色にならない問題

## Context

`komorebi.json` の `theme` 内で `"focused_border": "#00BFFF"` を指定しているが、フォーカスウィンドウのボーダーが水色にならない。

## 原因（2つ）

### 1. `focused_border` というフィールドは存在しない

Base16 テーマのスキーマに `focused_border` は定義されていない。正しいフィールド名は状態別：

| フィールド             | 意味                           |
| ---------------------- | ------------------------------ |
| `single_border`        | 単一ウィンドウ（通常のフォーカス状態） |
| `stack_border`         | スタック時                     |
| `monocle_border`       | モノクル時                     |
| `floating_border`      | フローティング時               |
| `unfocused_border`     | 非フォーカス                   |

### 2. Base16 テーマでは hex カラーを使えない

`"palette": "Base16"` 使用時、ボーダー色は `Base00`〜`Base0F` のパレット参照のみ有効。`"#00BFFF"` のような hex 値は受け付けない。

## 修正方針

`komorebi.json` から `theme` を削除し、`border_colours` で hex カラーを直接指定する。

`komorebi.bar.json` は独自に `theme` を持っているため、影響なし。

### ファイル: `komorebi.json`

**削除:**

```json
"theme": {
    "palette": "Base16",
    "name": "Ashes",
    "focused_border": "#00BFFF",
    "unfocused_border": "Base03",
    "bar_accent": "Base0D"
}
```

**追加:**

```json
"border_colours": {
    "single": "#00BFFF",
    "stack": "#00BFFF",
    "monocle": "#00BFFF",
    "unfocused": "#747C84"
}
```

- `#747C84` = Ashes Base03（元の unfocused_border と同等）
- single/stack/monocle すべてに `#00BFFF` を設定し、どの状態でもフォーカスウィンドウが水色になるようにする

## 検証

1. komorebi 再起動後、ウィンドウにフォーカスした際にボーダーが水色になるか確認
2. 非フォーカスウィンドウのボーダーがグレーになるか確認
3. komorebi-bar の表示が崩れていないか確認
