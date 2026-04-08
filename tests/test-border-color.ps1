#!/usr/bin/env pwsh
# テスト: フォーカス中ウィンドウのボーダー色がシアン (#00FFFF) かどうかを確認する
# スクリーンショットを撮り、ボーダー付近のピクセル色をスポイトのように取得して判定する

# .NETのGUI系ライブラリを読み込む（スクリーンショット撮影に必要）
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 期待するボーダー色を定義（シアン = #00FFFF / Cyan）
# R(赤)=0x00, G(緑)=0xFF, B(青)=0xFF の組み合わせ
$expectedHex = "#00FFFF"
$expectedR = 0x00
$expectedG = 0xFF
$expectedB = 0xFF

# --- スクリーンショットを撮る ---
# 画面全体を1枚の画像としてメモリ上にキャプチャする
$screen = [System.Windows.Forms.Screen]::PrimaryScreen
$bitmap = New-Object System.Drawing.Bitmap($screen.Bounds.Width, $screen.Bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($screen.Bounds.Location, [System.Drawing.Point]::Empty, $screen.Bounds.Size)
$graphics.Dispose()

# 画面の幅(w)と高さ(h)を取得
$w = $bitmap.Width
$h = $bitmap.Height

# 見つかった辺の数と、どこで見つかったかを記録する変数
$found = 0
$sides = @()

# --- 上辺のボーダーを探す ---
# 画面の横方向の中央(cx)で、上端(y=0)から下へ100pxまでスキャン
# 期待する色のピクセルが見つかったら「上辺にボーダーあり」と判定
$cx = [int]($w / 2)
for ($y = 0; $y -lt [Math]::Min(100, $h); $y++) {
    $pixel = $bitmap.GetPixel($cx, $y)
    if ($pixel.R -eq $expectedR -and $pixel.G -eq $expectedG -and $pixel.B -eq $expectedB) {
        $sides += "top(x=$cx,y=$y)"
        $found++
        break
    }
}

# --- 左辺のボーダーを探す ---
# 画面の縦方向の中央(cy)で、左端(x=0)から右へ100pxまでスキャン
$cy = [int]($h / 2)
for ($x = 0; $x -lt [Math]::Min(100, $w); $x++) {
    $pixel = $bitmap.GetPixel($x, $cy)
    if ($pixel.R -eq $expectedR -and $pixel.G -eq $expectedG -and $pixel.B -eq $expectedB) {
        $sides += "left(x=$x,y=$cy)"
        $found++
        break
    }
}

# --- 右辺のボーダーを探す ---
# 画面の右端から左へ100pxまでスキャン
for ($x = $w - 1; $x -ge [Math]::Max($w - 100, 0); $x--) {
    $pixel = $bitmap.GetPixel($x, $cy)
    if ($pixel.R -eq $expectedR -and $pixel.G -eq $expectedG -and $pixel.B -eq $expectedB) {
        $sides += "right(x=$x,y=$cy)"
        $found++
        break
    }
}

# --- 下辺のボーダーを探す ---
# 画面の下端から上へ100pxまでスキャン
for ($y = $h - 1; $y -ge [Math]::Max($h - 100, 0); $y--) {
    $pixel = $bitmap.GetPixel($cx, $y)
    if ($pixel.R -eq $expectedR -and $pixel.G -eq $expectedG -and $pixel.B -eq $expectedB) {
        $sides += "bottom(x=$cx,y=$y)"
        $found++
        break
    }
}

# 使い終わった画像をメモリから解放
$bitmap.Dispose()

# --- 結果を表示 ---
Write-Output "Expected border color: $expectedHex"
Write-Output "Sides with exact match: $found / 4"
foreach ($s in $sides) {
    Write-Output "  PASS: $s"
}

# 4辺のうち2辺以上で色が一致すればテスト成功
# （ウィンドウ配置によっては一部の辺が画面端と重なり検出できない場合があるため）
if ($found -ge 2) {
    Write-Output "RESULT: PASS - border color is $expectedHex"
    exit 0
} else {
    Write-Output "RESULT: FAIL - border color $expectedHex not found on enough sides"
    exit 1
}
