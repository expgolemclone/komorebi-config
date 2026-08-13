# komorebi-config

Windows tiling window manager [komorebi][komorebi]の個人用設定です.

komorebiにmonitorを自動検出させ, 各monitorでworkspace 0を1つだけ使用します. 起動時に全workspaceへ`Rows` layoutを適用します.

## Requirements

- PowerShell 7
- [komorebi][komorebi]
- [whkd][whkd]
- JetBrains Mono
- jjとuv, unit testを実行する場合のみ

## Setup

管理者PowerShell 7でrepository rootへ移動し, Scheduled Taskを登録します.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\register-task.ps1
```

Taskは現在のcheckoutにある`restart.ps1`の絶対pathを保存し, loginの30秒後に最高権限で実行します. Repositoryを移動した場合は, 同じcommandでTaskを再登録します.

手動で起動または再起動する場合は, 次のcommandを実行します.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\restart.ps1
```

`restart.ps1`はrepository rootをconfig rootとして解決し, 次の処理を行います.

1. `KOMOREBI_CONFIG_HOME`と`WHKD_CONFIG_HOME`を設定します.
2. `LowLevelHooksTimeout`を5000 msへ設定します.
3. komorebi, komorebi-bar, whkdを正式なCLIで停止します.
4. 孤立したbar socket fileを削除します.
5. Static configを指定して3 processを起動します.
6. 自動検出した各monitorのworkspace 0へ`Rows`を適用します.

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
uv run pytest -q
uv run python .\scripts\validate_encoding.py
```

実機のkomorebi状態を検証する場合は, restart後にintegration testを明示実行します.

```powershell
uv run pytest -q tests\integration\test_komorebi_runtime.py
pwsh -NoProfile -File .\tests\integration\windows\test-restart.ps1
pwsh -NoProfile -File .\tests\integration\windows\test-border-color.ps1
```

[komorebi]: https://github.com/LGUG2Z/komorebi
[whkd]: https://github.com/LGUG2Z/whkd
