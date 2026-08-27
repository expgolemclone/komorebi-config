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


def test_restart_requires_explicit_elevation() -> None:
    content = _content("restart.ps1")

    assert 'throw "restart.ps1 must be run from an elevated PowerShell 7 session"' in content
    assert "-Verb RunAs" not in content
    assert "-Wait `" not in content


def test_restart_uses_official_process_lifecycle() -> None:
    content = _content("restart.ps1")

    assert 'ArgumentList @("stop", "--whkd", "--bar")' in content
    assert 'Where-Object Name -eq "komorebi"' in content
    assert "Stopping orphaned helper processes" in content
    assert (
        'ArgumentList @("start", "--config", $configPath, "--whkd", "--bar", "--clean-state")'
        in content
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

    assert "function Invoke-Komorebic" in content
    assert "[System.Diagnostics.ProcessStartInfo]::new()" in content
    assert "$process.WaitForExit($TimeoutMilliseconds)" in content
    assert "$process.Kill($true)" in content
    assert "timed out after $seconds seconds" in content
    assert "failed with exit code $($process.ExitCode)" in content
    assert "& $komorebicPath" not in content

    for operation in (
        '"stop"',
        '"data-directory"',
        '"start"',
        '"monitor-information"',
        '"workspace-layout monitor $monitorIndex workspace 0 -> $layout"',
    ):
        assert f"-Operation {operation}" in content


def test_restart_reports_progress_before_runtime_operations() -> None:
    content = _content("restart.ps1")

    for stage in (
        "=== Stopping komorebi ===",
        "=== Cleaning runtime files ===",
        "=== Starting komorebi ===",
        "=== Waiting for managed processes ===",
        "=== Applying workspace layouts ===",
        "=== Running processes ===",
    ):
        assert stage in content


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
