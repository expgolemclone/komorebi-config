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
- jjとuv, unit testを実行する場合のみ

## Setup

Scheduled Task `\komorebi` の定義と登録は, [task-scheduler-managementの`komorebi.xml`](https://github.com/expgolemclone/task-scheduler-management/blob/main/scheduled-tasks/definitions/komorebi.xml) で管理します.

既存のAutoHotkey UIAccess processは`WM_DISPLAYCHANGE`を受信し, `QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS)`でactiveな物理display targetの集合を確認します. 2秒間変化が落ち着いた後にtarget集合が変わっていれば, Task Scheduler COM APIで既存の`\komorebi`をon-demand実行します. 接続, 切断, 同数のmonitor交換では再起動し, 解像度, 回転, primary monitorだけの変更では再起動しません. 監視用の追加process, polling loop, service, WMI consumerは使用しません.

手動で起動または再起動する場合は, PowerShell 7で次のcommandを実行します. `restart.ps1`は非管理者sessionではUACを表示し, 許可後に管理者processで処理を続行します.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\restart.ps1
```

`restart.ps1`はrepository rootをconfig rootとして解決し, 次の処理を行います.

1. `KOMOREBI_CONFIG_HOME`と`WHKD_CONFIG_HOME`を設定します.
2. `LowLevelHooksTimeout`をWindowsの上限である1000 msへ設定します.
3. komorebi, komorebi-bar, whkdの既存processを終了します.
4. Static configを指定してkomorebiを起動し, IPC serverの応答後にwhkdを起動します. komorebi-barは起動しません.
5. 自動検出した各monitorのworkspace 0へ, 横長なら`Columns`, 縦長なら`Rows`を適用します.
6. Windowsの`DisplayEnhancementService`を再起動し, 夜間モードの表示効果を再適用します.

2 processは検証済みの実体pathとconfig pathを指定して直接起動するため, `komorebic start`のnetwork更新確認に再起動を依存させません. すべての`komorebic`呼び出しにはtimeoutがあり, 実行前にstage名を表示します. CLIが応答しない場合はhangし続けず, timeoutしたoperation名を含むerrorで終了します.

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
uv run --extra test pytest -q
uv run python .\scripts\validate_encoding.py
```

実機のkomorebi状態を検証する場合は, restart後にintegration testを明示実行します.

```powershell
pwsh -NoProfile -File .\tests\integration\windows\test-restart.ps1
uv run --extra test pytest -q tests\integration\test_komorebi_runtime.py
pwsh -NoProfile -File .\tests\integration\windows\test-config-schema.ps1
pwsh -NoProfile -File .\tests\integration\windows\test-cursor-helper.ps1
pwsh -NoProfile -File .\tests\integration\windows\test-border-color.ps1
```

[komorebi]: https://github.com/LGUG2Z/komorebi
[whkd]: https://github.com/LGUG2Z/whkd
