"""Tests for Windows VM setup script."""

import subprocess
import sys
import textwrap
from pathlib import Path

COMPOSE_FILE: Path = Path(__file__).resolve().parent.parent / "docker-compose.windows.yml"
SETUP_SCRIPT: Path = Path(__file__).resolve().parent.parent / "tests" / "setup_windows_vm.py"


def test_compose_file_exists() -> None:
    assert COMPOSE_FILE.exists(), f"{COMPOSE_FILE} not found"


def test_compose_file_valid_yaml() -> None:
    import yaml

    with open(COMPOSE_FILE, encoding="utf-8") as f:
        data: dict[str, object] = yaml.safe_load(f)

    assert "services" in data
    assert "windows" in data["services"]  # type: ignore[operator]


def test_compose_has_kvm_device() -> None:
    import yaml

    with open(COMPOSE_FILE, encoding="utf-8") as f:
        data: dict[str, object] = yaml.safe_load(f)

    windows_service: dict[str, object] = data["services"]["windows"]  # type: ignore[index]
    devices: list[str] = windows_service["devices"]  # type: ignore[assignment]
    assert "/dev/kvm" in devices


def test_compose_has_shared_volume() -> None:
    import yaml

    with open(COMPOSE_FILE, encoding="utf-8") as f:
        data: dict[str, object] = yaml.safe_load(f)

    windows_service: dict[str, object] = data["services"]["windows"]  # type: ignore[index]
    volumes: list[str] = windows_service["volumes"]  # type: ignore[assignment]
    assert any("shared" in v for v in volumes)


def test_setup_script_exists() -> None:
    assert SETUP_SCRIPT.exists(), f"{SETUP_SCRIPT} not found"


def test_setup_script_generates_powershell() -> None:
    result: subprocess.CompletedProcess[str] = subprocess.run(
        [sys.executable, str(SETUP_SCRIPT), "--dry-run"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0
    assert "winget install" in result.stdout
    assert "komorebi" in result.stdout.lower()
