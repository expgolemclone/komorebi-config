#requires -Version 7.0

$ErrorActionPreference = "Stop"
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class DpiAwareness
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr dpiContext);
}
'@

$previousDpiContext = [DpiAwareness]::SetThreadDpiAwarenessContext([IntPtr](-4))
if ($previousDpiContext -eq [IntPtr]::Zero) {
    $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    throw "failed to enable per-monitor DPI awareness: Win32 error $errorCode"
}
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$expected = [System.Drawing.Color]::FromArgb(0, 255, 255)
$state = komorebic state | ConvertFrom-Json
$monitor = $state.monitors.elements[$state.monitors.focused]
$workspace = $monitor.workspaces.elements[$monitor.workspaces.focused]
$container = $workspace.containers.elements[$workspace.containers.focused]
$window = $container.windows.elements[$container.windows.focused]

if (-not $window) {
    Write-Host "FAIL: komorebi has no focused tiled window" -ForegroundColor Red
    exit 1
}

$screen = [System.Windows.Forms.Screen]::FromHandle([IntPtr]$window.hwnd)
$bitmap = [System.Drawing.Bitmap]::new($screen.Bounds.Width, $screen.Bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)

try {
    $graphics.CopyFromScreen(
        $screen.Bounds.Location,
        [System.Drawing.Point]::Empty,
        $screen.Bounds.Size
    )

    $width = $bitmap.Width
    $height = $bitmap.Height
    $windowLeft = [int]$window.rect.left - $screen.Bounds.Left
    $windowTop = [int]$window.rect.top - $screen.Bounds.Top
    $windowRight = $windowLeft + [int]$window.rect.right - 1
    $windowBottom = $windowTop + [int]$window.rect.bottom - 1
    $middleX = [Math]::Clamp([int](($windowLeft + $windowRight) / 2), 0, $width - 1)
    $middleY = [Math]::Clamp([int](($windowTop + $windowBottom) / 2), 0, $height - 1)
    $searchRadius = 16
    $matches = 0

    $samples = @(
        @{
            Axis  = "Y"
            Fixed = $middleX
            Start = [Math]::Max(0, $windowTop - $searchRadius)
            End   = [Math]::Min($height - 1, $windowTop + $searchRadius)
        },
        @{
            Axis  = "X"
            Fixed = $middleY
            Start = [Math]::Max(0, $windowLeft - $searchRadius)
            End   = [Math]::Min($width - 1, $windowLeft + $searchRadius)
        },
        @{
            Axis  = "X"
            Fixed = $middleY
            Start = [Math]::Max(0, $windowRight - $searchRadius)
            End   = [Math]::Min($width - 1, $windowRight + $searchRadius)
        },
        @{
            Axis  = "Y"
            Fixed = $middleX
            Start = [Math]::Max(0, $windowBottom - $searchRadius)
            End   = [Math]::Min($height - 1, $windowBottom + $searchRadius)
        }
    )

    foreach ($sample in $samples) {
        for ($position = $sample.Start; $position -le $sample.End; $position++) {
            if ($sample.Axis -eq "X") {
                $pixel = $bitmap.GetPixel($position, $sample.Fixed)
            }
            else {
                $pixel = $bitmap.GetPixel($sample.Fixed, $position)
            }
            if ($pixel.R -eq $expected.R -and
                $pixel.G -eq $expected.G -and
                $pixel.B -eq $expected.B) {
                $matches++
                break
            }
        }
    }
}
finally {
    $graphics.Dispose()
    $bitmap.Dispose()
    if ($previousDpiContext -ne [IntPtr]::Zero) {
        [void][DpiAwareness]::SetThreadDpiAwarenessContext($previousDpiContext)
    }
}

if ($matches -lt 2) {
    Write-Host "FAIL: cyan border was found on only $matches focused window edges" -ForegroundColor Red
    exit 1
}

Write-Host "PASS: cyan border was found on $matches focused window edges" -ForegroundColor Green
exit 0
