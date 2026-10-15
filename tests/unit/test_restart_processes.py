"""Exercise restart functions without touching managed processes or services."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

RESTART = Path(__file__).resolve().parents[2] / "scripts" / "restart.ps1"
LOAD_FUNCTIONS = r"""
$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $Env:RESTART_SCRIPT, [ref]$tokens, [ref]$errors
)
if ($errors.Count) { throw 'restart.ps1 has parse errors' }
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
        . ([scriptblock]::Create($statement.Extent.Text))
    }
}
"""


def _run(command: str, **environment: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "pwsh", "-NoProfile", "-NonInteractive", "-Command",
            LOAD_FUNCTIONS + command + "\nexit 0\n",
        ],
        env={**os.environ, "RESTART_SCRIPT": str(RESTART), **environment},
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=15,
    )


@pytest.mark.parametrize("clean_state", [False, True], ids=["whkd", "komorebi"])
def test_managed_process_preserves_config_argument(
    tmp_path: Path, clean_state: bool
) -> None:
    helper = tmp_path / "capture.py"
    helper.write_text(
        "import json, os, sys\n"
        "from pathlib import Path\n"
        "output = Path(os.environ['CAPTURE_FILE'])\n"
        "pending = output.with_suffix('.tmp')\n"
        "pending.write_text(json.dumps(sys.argv[1:]), encoding='utf-8')\n"
        "pending.replace(output)\n",
        encoding="utf-8",
    )
    output = tmp_path / "arguments.json"
    arguments = ["--config", str(tmp_path / "設定 with spaces" / "config.json")]
    if clean_state:
        arguments.append("--clean-state")

    result = _run(
        r"""
$arguments = @(ConvertFrom-Json $Env:CHILD_ARGUMENTS)
Start-ManagedProcess -FilePath $Env:CHILD_EXECUTABLE `
    -ArgumentList $arguments -ProcessName 'argument capture'
$deadline = [DateTime]::UtcNow.AddSeconds(5)
while (-not (Test-Path -LiteralPath $Env:CAPTURE_FILE)) {
    if ([DateTime]::UtcNow -ge $deadline) { throw 'child did not capture arguments' }
    Start-Sleep -Milliseconds 50
}
""",
        CHILD_EXECUTABLE=sys.executable,
        CHILD_ARGUMENTS=json.dumps([str(helper), *arguments]),
        CAPTURE_FILE=str(output),
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert json.loads(output.read_text(encoding="utf-8")) == arguments


def test_native_command_reports_failure_output() -> None:
    result = _run(
        r"""
try {
    Invoke-NativeCommand -FilePath (Join-Path $PSHOME 'pwsh.exe') `
        -ArgumentList @('-NoProfile', '-NonInteractive', '-Command',
            '[Console]::Out.WriteLine("output detail"); [Console]::Error.WriteLine("error detail"); exit 7') `
        -Operation 'failure probe' -CommandName 'pwsh'
    throw 'expected command failure'
} catch {
    if ($_.Exception.Message -notlike '*failed with exit code 7*') { throw }
    if ($_.Exception.Message -notlike '*stdout: output detail*') { throw }
    if ($_.Exception.Message -notlike '*stderr: error detail*') { throw }
}
"""
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_native_command_timeout_terminates_child(tmp_path: Path) -> None:
    result = _run(
        r"""
$elapsed = [Diagnostics.Stopwatch]::StartNew()
try {
    Invoke-NativeCommand -FilePath (Join-Path $PSHOME 'pwsh.exe') `
        -ArgumentList @('-NoProfile', '-NonInteractive', '-Command',
            'Set-Content -LiteralPath $Env:CHILD_PID_FILE -Value $PID; Start-Sleep -Seconds 60') `
        -Operation 'timeout probe' -CommandName 'pwsh' -TimeoutMilliseconds 1500
    throw 'expected timeout'
} catch {
    if ($_.Exception.Message -notlike '*timeout probe timed out after 1.5 seconds*') { throw }
}
if ($elapsed.Elapsed.TotalSeconds -gt 8) { throw 'timeout was not bounded' }
$childId = [int](Get-Content -LiteralPath $Env:CHILD_PID_FILE)
if (Get-Process -Id $childId -ErrorAction SilentlyContinue) { throw 'child survived timeout' }
""",
        CHILD_PID_FILE=str(tmp_path / "child.pid"),
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_night_light_restarts_only_inside_bounded_child() -> None:
    result = _run(
        r"""
# Never allow this test to touch the actual Windows service.
function Restart-Service { throw 'service restart must run inside bounded child' }
function Invoke-NativeCommand {
    param($FilePath, $ArgumentList, $Operation, $CommandName, $TimeoutMilliseconds)
    if ($FilePath -ne (Join-Path $PSHOME 'pwsh.exe')) { throw 'unexpected child executable' }
    if ($TimeoutMilliseconds -ne 1234) { throw 'service deadline was not forwarded' }
    if ($ArgumentList -notcontains '-NoProfile') { throw 'child profile is enabled' }
    if ($ArgumentList -notcontains '-NonInteractive') { throw 'child can prompt' }
    if ($Operation -notlike '*DisplayEnhancementService*') { throw 'operation lacks service name' }
    $commandIndex = [Array]::IndexOf($ArgumentList, '-Command')
    if ($commandIndex -lt 0) { throw 'missing service command' }
    function Restart-Service {
        param($Name, [switch]$Force, $ErrorAction)
        if ($Name -ne 'DisplayEnhancementService') { throw 'wrong service' }
        if (-not $Force) { throw 'missing Force' }
        if ($ErrorAction -ne 'Stop') { throw 'service errors are not terminating' }
        $script:serviceCommandVerified = $true
    }
    & ([scriptblock]::Create($ArgumentList[$commandIndex + 1]))
    throw 'bounded child failure'
}
try {
    Restart-WindowsNightLight -TimeoutMilliseconds 1234
    throw 'child failure was swallowed'
} catch {
    if ($_.Exception.Message -ne 'bounded child failure') { throw }
}
if (-not $script:serviceCommandVerified) { throw 'service command was not verified' }
"""
    )
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.parametrize("scenario", ["settings", "empty", "missing-data"])
def test_night_light_snapshot_reads_settings_not_state(scenario: str) -> None:
    result = _run(
        r"""
function Get-ChildItem {
    param($LiteralPath, [switch]$Recurse, $ErrorAction)
    if ($LiteralPath -notlike '*\DefaultAccount\Current') {
        throw 'snapshot must read Current settings, not Cloud metadata'
    }
    if ($Env:SNAPSHOT_CASE -eq 'empty') { return }
    foreach ($kind in @('settings', 'settingsperdevice',
        'bluelightreductionstate', 'bluelightreductionstateperdevice')) {
        $name = "windows.data.bluelightreduction.$kind"
        [pscustomobject]@{ Name = $name; PSPath = $name; PSChildName = $name }
    }
}
function Get-ItemProperty {
    param($LiteralPath, $ErrorAction)
    if ($LiteralPath -like '*state*') { throw 'snapshot included dynamic state' }
    $data = if ($Env:SNAPSHOT_CASE -eq 'missing-data') { $null } else { [byte[]]@(1, 2) }
    [pscustomobject]@{ Data = $data }
}
if ($Env:SNAPSHOT_CASE -eq 'settings') {
    $expected = "windows.data.bluelightreduction.settings=0102`n" +
        'windows.data.bluelightreduction.settingsperdevice=0102'
    if ((Get-NightLightDataSnapshot) -cne $expected) { throw 'settings snapshot is incomplete' }
} else {
    try {
        Get-NightLightDataSnapshot
        throw 'missing settings were accepted'
    } catch {
        if ($_.Exception.Message -ne 'Night Light settings data was not found') { throw }
    }
}
""",
        RESTART_SCRIPT=str(
            RESTART.parents[1] / "tests/integration/windows/test-restart.ps1"
        ),
        SNAPSHOT_CASE=scenario,
    )
    assert result.returncode == 0, result.stdout + result.stderr
