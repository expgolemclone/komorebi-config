#requires -Version 7.0

$ErrorActionPreference = "Stop"

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class CursorTestNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct Point
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr dpiContext);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetWindowRect(IntPtr window, out Rect rect);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetCursorPos(out Point point);
}
'@

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..\..")).Path
$helperPath = Join-Path $repoRoot "scripts\move-cursor-bottom-center.ahk"
$autoHotkeyInstallLocation = Get-ItemPropertyValue `
    -LiteralPath "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AutoHotkey" `
    -Name "InstallLocation" `
    -ErrorAction Stop
$autoHotkeyPath = Join-Path $autoHotkeyInstallLocation "v2\AutoHotkey64.exe"
if (-not (Test-Path -LiteralPath $autoHotkeyPath -PathType Leaf)) {
    throw "AutoHotkey v2 executable was not found: $autoHotkeyPath"
}

$previousDpiContext = [CursorTestNative]::SetThreadDpiAwarenessContext([IntPtr](-4))
if ($previousDpiContext -eq [IntPtr]::Zero) {
    throw "failed to enable per-monitor DPI awareness"
}

try {
    $window = [CursorTestNative]::GetForegroundWindow()
    $rect = [CursorTestNative+Rect]::new()
    if (-not [CursorTestNative]::GetWindowRect($window, [ref]$rect)) {
        throw "failed to read the foreground window bounds"
    }

    $processInfo = [Diagnostics.ProcessStartInfo]::new($autoHotkeyPath)
    $processInfo.ArgumentList.Add($helperPath)
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $process = [Diagnostics.Process]::Start($processInfo)
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "cursor helper failed with exit code $($process.ExitCode)"
    }

    $position = [CursorTestNative+Point]::new()
    if (-not [CursorTestNative]::GetCursorPos([ref]$position)) {
        throw "failed to read the cursor position"
    }

    $expectedX = [int](($rect.Left + $rect.Right) / 2)
    $expectedY = $rect.Bottom - 10
    if ($position.X -ne $expectedX -or $position.Y -ne $expectedY) {
        throw "unexpected cursor position: $($position.X),$($position.Y)"
    }
} finally {
    [void][CursorTestNative]::SetThreadDpiAwarenessContext($previousDpiContext)
}

Write-Host "PASS: cursor helper moved to $expectedX,$expectedY" -ForegroundColor Green
exit 0
