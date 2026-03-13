# test-whkdrc-workspace-keys.ps1
# whkdrc のワークスペースキーが komorebi.json のワークスペース数と一致するか検証する

$configPath = "$PSScriptRoot\..\komorebi.json"
$whkdrcPath = "$PSScriptRoot\..\whkdrc"

$config = Get-Content $configPath | ConvertFrom-Json
$wsCount = $config.monitors[0].workspaces.Count

$whkdrc = Get-Content $whkdrcPath -Raw

$allPass = $true

# focus-workspace で参照されるインデックスを抽出
$focusMatches = [regex]::Matches($whkdrc, 'focus-workspace\s+(\d+)')
foreach ($m in $focusMatches) {
    $idx = [int]$m.Groups[1].Value
    if ($idx -ge $wsCount) {
        Write-Host "FAIL: focus-workspace $idx references non-existent workspace (max index: $($wsCount - 1))" -ForegroundColor Red
        $allPass = $false
    }
}

# move-to-workspace で参照されるインデックスを抽出
$moveMatches = [regex]::Matches($whkdrc, 'move-to-workspace\s+(\d+)')
foreach ($m in $moveMatches) {
    $idx = [int]$m.Groups[1].Value
    if ($idx -ge $wsCount) {
        Write-Host "FAIL: move-to-workspace $idx references non-existent workspace (max index: $($wsCount - 1))" -ForegroundColor Red
        $allPass = $false
    }
}

if ($allPass) {
    Write-Host "PASS: all workspace key bindings reference valid workspace indices (0..$($wsCount - 1))" -ForegroundColor Green
    exit 0
} else {
    exit 1
}
