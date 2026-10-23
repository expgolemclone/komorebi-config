# komorebi-config

Personal Windows configuration for [komorebi][komorebi] v0.1.41 and [whkd][whkd], with native Rust restart and cursor helpers.

Monitors are detected automatically. Each uses workspace 0 with Columns on landscape monitors and Rows otherwise. Classic console windows and Office documents are managed; Classic Outlook and Office helper windows are excluded.

## Setup

The scheduled task `\komorebi` is managed by [task-scheduler-management](https://github.com/expgolemclone/task-scheduler-management). It runs the installed helper through `task-runner.exe`, elevated, immediately after logon. Register or update it locally with the selected deployment profile. [AutoHotkey](https://github.com/expgolemclone/autohotkey) owns monitor-change restart requests, not this helper.

```powershell
komorebi-config restart --config-directory C:/dev/settings/komorebi-config
```

Restart requests administrator privileges when necessary, validates configuration, replaces komorebi/whkd, and verifies monitor layouts before releasing the daemons. It does not reset displays or start komorebi-bar. Logs: `%LOCALAPPDATA%/komorebi/restart.log`.

`komorebi-config restart --config-directory C:/dev/settings/komorebi-config --recover-display` additionally resets the display adapter and restarts the Night Light service. Use only for deliberate graphics recovery; displays briefly go dark.

See [whkdrc](whkdrc) for all bindings. The cursor helper does not require AutoHotkey or elevation. Upstream komorebic retains its PowerShell dependency.

## Tests

```powershell
cargo fmt --all -- --check
cargo clippy --locked --all-targets --features live-tests -- -D warnings
cargo test --locked --release --features process-tests
```

Explicit read-only runtime checks and disposable tests under the installed supervisor:

```powershell
cargo test --locked --release --features live-tests --test live --test process
```

These tests do not restart the desktop, move the cursor, or reset displays.

[komorebi]: https://github.com/LGUG2Z/komorebi
[whkd]: https://github.com/LGUG2Z/whkd
