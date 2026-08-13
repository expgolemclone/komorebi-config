#Requires AutoHotkey v2.0
#SingleInstance Force

window := WinExist("A")
if !window
    ExitApp 1

WinGetPos(&x, &y, &width, &height, "ahk_id " window)
targetX := x + width // 2
targetY := y + height - 10
if !DllCall("SetCursorPos", "Int", targetX, "Int", targetY)
    ExitApp 2

ExitApp 0
