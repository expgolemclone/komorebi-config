"""Windows VM setup構成を検証する。"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
COMPOSE_FILE = ROOT / "docker-compose.windows.yml"
SETUP_SCRIPT = ROOT / "tests" / "setup_windows_vm.py"


def _compose_config() -> dict:
    with COMPOSE_FILE.open(encoding="utf-8") as file:
        return yaml.safe_load(file)


def test_compose_defines_windows_vm_with_kvm_and_shared_folder() -> None:
    windows = _compose_config()["services"]["windows"]

    assert "/dev/kvm" in windows["devices"]
    assert any("shared" in volume for volume in windows["volumes"])


def test_setup_script_generates_powershell() -> None:
    result = subprocess.run(
        [sys.executable, str(SETUP_SCRIPT), "--dry-run"],
        capture_output=True,
        text=True,
        timeout=10,
    )

    assert result.returncode == 0
    assert "Microsoft.PowerShell" in result.stdout
    assert "winget install" in result.stdout
    assert "komorebi" in result.stdout.lower()
    assert "GetEnvironmentVariable" in result.stdout
    assert "\\\\host.lan\\Data" in result.stdout
    assert "C:\\shared" not in result.stdout
    assert "tests\\integration\\windows\\test-restart.ps1" in result.stdout
