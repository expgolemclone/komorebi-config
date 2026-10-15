# komorebi-config

Windows tiling window manager [komorebi][komorebi]の個人用設定です.

komorebiにmonitorを自動検出させ, 各monitorでworkspace 0を1つだけ使用します. 起動時に横長monitorへ`Columns`, 縦長monitorへ`Rows` layoutを適用します.
Classic console windowは`ConsoleWindowClass`で強制的に管理し, 管理者権限で起動したPowerShellも整列対象に含めます. Classic Outlookは`OUTLOOK.EXE`のignore ruleで管理対象外にします.
Excel, PowerPoint, Wordはそれぞれ`EXCEL.EXE`, `POWERPNT.EXE`, `WINWORD.EXE`をlayered applicationとして管理し, `_WwB` classのpopupと補助windowだけを管理対象外にします.

## Requirements

- PowerShell 7
- [komorebi][komorebi] v0.1.41
- [whkd][whkd]
- AutoHotkey v2.0.26
- jjとenvxの共通Python環境, unit testを実行する場合のみ

## Setup

Scheduled Task `\komorebi` の定義と登録は, [task-scheduler-managementの`komorebi.xml`](https://github.com/expgolemclone/task-scheduler-management/blob/main/scheduled-tasks/definitions/komorebi.xml) で管理します.

Monitor-change restart behavior is owned by [autohotkey](https://github.com/expgolemclone/autohotkey).

手動で起動または再起動する場合は, PowerShell 7で次のcommandを実行します. `restart.ps1`は非管理者sessionではUACを表示し, 許可後に管理者processで処理を続行します.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\restart.ps1
```

Restart uses the mapped configuration, restarts the display adapter and komorebi/whkd, reapplies night light and selects the layout for each monitor's orientation. Displays go dark briefly. It does not start komorebi-bar. A failed stage reports an error rather than waiting indefinitely.

## Key bindings

| Key | Action |
| --- | --- |
| `Alt + Q` | Windowを閉じる |
| `Alt + M` | Windowを最小化する |
| `Alt + T` | Floatingを切り替える |
| `Alt + Shift + F` | Monocleを切り替える |
| `Alt + H/J/K/L` | Focusを左, 下, 上, 右へ移動する |
| `Alt + Shift + H/J/K/L` | Windowを左, 下, 上, 右へ移動する |
| `Alt + 1` | Workspace 0へfocusする |
| `Alt + Shift + 1` | Windowをworkspace 0へ移動する |
| `Alt + O` | whkdを再起動する |
| `Alt + Shift + O` | `komorebi.json`をrunning instanceへ反映する |

その他のbindingは[whkdrc](whkdrc)を参照してください.

## Tests

通常のtestはhardwareやrunning processに依存しません.

```powershell
envx-python -m pytest -q
envx-python .\scripts\validate_encoding.py
```

実機のkomorebi状態を検証する場合は, restart後にintegration testを明示実行します.

```powershell
pwsh -NoProfile -File .\tests\integration\windows\test-restart.ps1
python -m pytest -q tests\integration\test_komorebi_runtime.py
pwsh -NoProfile -File .\tests\integration\windows\test-config-schema.ps1
pwsh -NoProfile -File .\tests\integration\windows\test-cursor-helper.ps1
pwsh -NoProfile -File .\tests\integration\windows\test-border-color.ps1
```

[komorebi]: https://github.com/LGUG2Z/komorebi
[whkd]: https://github.com/LGUG2Z/whkd
