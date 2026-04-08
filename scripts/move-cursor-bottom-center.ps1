# move-cursor-bottom-center.ps1
# フォーカス先ウィンドウの下辺中央にマウスカーソルを移動する

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class CursorUtil {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetCursorPos(int X, int Y);
}
"@

$hwnd = [CursorUtil]::GetForegroundWindow()
$rect = New-Object CursorUtil+RECT

if ([CursorUtil]::GetWindowRect($hwnd, [ref]$rect)) {
    $x = [int](($rect.Left + $rect.Right) / 2)
    $y = $rect.Bottom - 10
    [CursorUtil]::SetCursorPos($x, $y) | Out-Null
}
