"""PowerShell scriptのportabilityと構文を検証する。"""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
WINDOWS_INTEGRATION_TESTS = ROOT / "tests" / "integration" / "windows"
POWERSHELL_SCRIPTS = sorted(
    [*SCRIPTS.glob("*.ps1"), *WINDOWS_INTEGRATION_TESTS.glob("*.ps1")]
)


def _content(name: str) -> str:
    return (SCRIPTS / name).read_text(encoding="utf-8")


def test_powershell_scripts_have_valid_syntax() -> None:
    parser_command = """
$path = [Environment]::GetEnvironmentVariable("KOMOREBI_TEST_PS1_PATH")
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $path,
    [ref]$tokens,
    [ref]$errors
) | Out-Null
if ($errors.Count -ne 0) {
    $errors | ForEach-Object { Write-Error $_.Message }
    exit 1
}
    """
    for path in POWERSHELL_SCRIPTS:
        environment = os.environ.copy()
        environment["KOMOREBI_TEST_PS1_PATH"] = str(path)
        result = subprocess.run(
            ["pwsh", "-NoProfile", "-Command", parser_command],
            capture_output=True,
            text=True,
            timeout=10,
            env=environment,
        )
        assert result.returncode == 0, f"{path.name}: {result.stderr}"


def test_scripts_do_not_contain_hardcoded_user_paths() -> None:
    hardcoded_user_path = re.compile(r"C:\\Users\\[^$\\]+\\", re.IGNORECASE)

    for path in POWERSHELL_SCRIPTS:
        matches = hardcoded_user_path.findall(path.read_text(encoding="utf-8"))
        assert matches == [], f"{path.name}: {matches}"


def test_restart_resolves_repository_root_from_script_path() -> None:
    content = _content("restart.ps1")

    assert "$PSScriptRoot" in content
    assert 'Join-Path $PSScriptRoot ".."' in content
    assert ".config\\komorebi" not in content
    assert "projects\\komorebi-config" not in content


def test_restart_accepts_explicit_command_directories() -> None:
    content = _content("restart.ps1")

    assert "[string]$KomorebiBin" in content
    assert "[string]$WhkdBin" in content
    assert "[string]$AutoHotkeyPath" in content
    assert '$Env:PATH = "$KomorebiBin;$WhkdBin;$Env:PATH"' in content
    assert 'SetEnvironmentVariable("KOMOREBI_AUTOHOTKEY"' in content


def test_restart_self_elevates_with_uac() -> None:
    content = _content("restart.ps1")

    assert "function Invoke-ElevatedRestart" in content
    assert '$startInfo.FileName = Join-Path $PSHOME "pwsh.exe"' in content
    assert "$startInfo.UseShellExecute = $true" in content
    assert '$startInfo.Verb = "RunAs"' in content
    assert "$startInfo.ArgumentList.Add($argument)" in content
    assert '"-File"' in content
    assert "$PSCommandPath" in content
    for parameter in ("KomorebiBin", "WhkdBin", "AutoHotkeyPath"):
        assert f'"-{parameter}"' in content
    assert "$process.WaitForExit()" in content
    assert "$process.ExitCode -ne 0" in content
    assert "NativeErrorCode -eq 1223" in content
    assert 'throw "restart.ps1 must be run from an elevated PowerShell 7 session"' not in content


def test_restart_prevents_concurrent_instances() -> None:
    content = _content("restart.ps1")

    assert "function Enter-RestartLock" in content
    assert '"Local\\komorebi-config-restart"' in content
    assert "$mutex.WaitOne(0)" in content
    assert "[Threading.AbandonedMutexException]" in content
    assert "Another restart.ps1 instance is already running" in content
    assert "$restartLock.ReleaseMutex()" in content
    assert "$restartLock.Dispose()" in content


def test_readme_documents_restart_uac_elevation() -> None:
    readme = (ROOT / "README.md").read_text(encoding="utf-8")

    assert "非管理者sessionではUACを表示" in readme
    assert "自己昇格せず" not in readme


def test_restart_uses_direct_process_lifecycle() -> None:
    content = _content("restart.ps1")

    assert "Stopping managed processes" in content
    assert "Stop-Process -Id $runningProcesses.Id -Force" in content
    assert "function Start-ManagedProcess" in content
    assert "function Wait-KomorebiReady" in content
    assert "Start-Process `" in content
    assert "-WindowStyle Hidden `" in content
    assert "-PassThru `" in content
    assert (
        'ArgumentList @("--config", $configPath, "--clean-state")'
        in content
    )
    assert 'ArgumentList @("--config", $whkdConfigPath)' in content
    assert "Get-Command komorebi-bar" not in content
    assert 'ProcessName "komorebi-bar"' not in content
    assert '@("komorebi", "komorebi-bar", "whkd")' in content
    assert '@("komorebi", "whkd")' in content
    assert 'ArgumentList @("stop", "--whkd", "--bar")' not in content
    assert (
        'ArgumentList @("start", "--config", $configPath, "--whkd", "--bar", "--clean-state")'
        not in content
    )
    assert 'ArgumentList @("monitor-information")' in content
    assert (
        'ArgumentList @("workspace-layout", [string]$monitorIndex, "0", $layout)'
        in content
    )


def test_restart_selects_layout_from_monitor_orientation() -> None:
    content = _content("restart.ps1")

    assert "$width = [int]$monitor.size.right" in content
    assert "$height = [int]$monitor.size.bottom" in content
    assert "if ($width -gt $height)" in content
    assert '$layout = "columns"' in content
    assert "} else {" in content
    assert '$layout = "rows"' in content
    assert (
        'throw "monitor $monitorIndex has invalid dimensions: ${width}x${height}"'
        in content
    )
    assert "has square dimensions" not in content


def test_restart_bounds_every_komorebic_call() -> None:
    content = _content("restart.ps1")

    assert "function Invoke-NativeCommand" in content
    assert "function Invoke-Komorebic" in content
    assert "[System.Diagnostics.ProcessStartInfo]::new()" in content
    assert "$process.WaitForExit($TimeoutMilliseconds)" in content
    assert "$process.Kill($true)" in content
    assert "timed out after $seconds seconds" in content
    assert "failed with exit code $($process.ExitCode)" in content
    assert "& $komorebicPath" not in content

    for operation in (
        '"readiness probe"',
        '"workspace-layout monitor $monitorIndex workspace 0 -> $layout"',
    ):
        assert f"-Operation {operation}" in content


def test_restart_restarts_the_single_display_adapter_before_komorebi() -> None:
    content = _content("restart.ps1")

    assert "function Get-SingleHealthyDisplayAdapter" in content
    assert '-Class "Display"' in content
    assert "-PresentOnly" in content
    assert '-Status "OK"' in content
    assert "expected exactly one healthy display adapter" in content
    assert "function Restart-DisplayAdapter" in content
    assert 'Join-Path $env:SystemRoot "System32\\pnputil.exe"' in content
    assert '@("/restart-device", [string]$DisplayAdapter.InstanceId)' in content
    assert "function Wait-DisplayPipelineReady" in content
    assert "[System.Windows.Forms.Screen]::AllScreens.Count" in content
    assert "$RequiredStableSamples = 5" in content
    assert "$TimeoutMilliseconds = 30000" in content
    assert "expected $activeScreenCount" in content

    stop_index = content.index("=== Stopping komorebi ===")
    adapter_index = content.index("=== Restarting display adapter ===")
    night_light_index = content.index("=== Restarting Windows Night Light ===")
    start_index = content.index("=== Starting komorebi ===")
    assert stop_index < adapter_index < night_light_index < start_index


def test_restart_reports_progress_before_runtime_operations() -> None:
    content = _content("restart.ps1")

    for stage in (
        "=== Stopping komorebi ===",
        "=== Restarting display adapter ===",
        "=== Restarting Windows Night Light ===",
        "=== Starting komorebi ===",
        "=== Waiting for komorebi ===",
        "=== Starting helper processes ===",
        "=== Waiting for managed processes ===",
        "=== Applying workspace layouts ===",
        "=== Running processes ===",
    ):
        assert stage in content


def test_restart_restarts_windows_night_light_after_display_recovery() -> None:
    content = _content("restart.ps1")

    assert "function Restart-WindowsNightLight" in content
    assert 'Restart-Service `' in content
    assert '-Name "DisplayEnhancementService"' in content
    assert "[System.ServiceProcess.ServiceControllerStatus]::Running" in content
    assert "[TimeSpan]::FromMilliseconds($TimeoutMilliseconds)" in content
    assert "CloudStore" not in content
    assert "Stop-Process -Name explorer" not in content

    display_index = content.index("=== Restarting display adapter ===")
    night_light_index = content.index("=== Restarting Windows Night Light ===")
    start_index = content.index("=== Starting komorebi ===")
    assert display_index < night_light_index < start_index


def test_restart_integration_tracks_display_and_preserves_night_light_data() -> None:
    content = (
        WINDOWS_INTEGRATION_TESTS / "test-restart.ps1"
    ).read_text(encoding="utf-8")

    assert "DEVPKEY_Device_LastArrivalDate" in content
    assert 'Start-ScheduledTask `' in content
    assert '-TaskName "komorebi"' in content
    assert '$taskInfoAfter.LastTaskResult -ne 0' in content
    assert "display adapter restarted and is healthy" in content
    assert "[System.Windows.Forms.Screen]::AllScreens.Count" in content
    assert "Night Light settings data was preserved" in content
    assert "komorebi detected every active screen" in content


def test_restart_uses_supported_hook_timeout() -> None:
    content = _content("restart.ps1")

    assert 'Name "LowLevelHooksTimeout"' in content
    assert "-Value 1000" in content
    assert "-Value 5000" not in content


def test_scheduled_task_registration_is_owned_by_task_scheduler_repository() -> None:
    assert not (SCRIPTS / "register-task.ps1").exists()
    assert not (SCRIPTS / "create-startup-shortcut.ps1").exists()


def test_cursor_helper_uses_autohotkey_v2_and_checks_win32_result() -> None:
    content = (SCRIPTS / "move-cursor-bottom-center.ahk").read_text(encoding="utf-8")
    restart = _content("restart.ps1")

    assert "#Requires AutoHotkey v2.0" in content
    assert "WinGetPos" in content
    assert 'if !DllCall("SetCursorPos"' in content
    assert "AutoHotkey64.exe" in restart
    assert "$Env:KOMOREBI_AUTOHOTKEY" in restart
    assert not (SCRIPTS / "move-cursor-bottom-center.ps1").exists()


def test_readme_uses_reproducible_test_commands_in_runtime_order() -> None:
    readme = (ROOT / "README.md").read_text(encoding="utf-8")

    assert "uv run --extra test pytest -q" in readme
    restart_index = readme.index("tests\\integration\\windows\\test-restart.ps1")
    runtime_index = readme.index("tests\\integration\\test_komorebi_runtime.py")
    assert restart_index < runtime_index
