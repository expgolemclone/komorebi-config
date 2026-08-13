"""Docker上のWindows VMが稼働していることを検証する。"""

from __future__ import annotations

import socket
import subprocess


def _docker(args: list[str]) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            ["docker", *args],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except FileNotFoundError as error:
        raise AssertionError("docker command is not installed") from error


def _port_open(port: int, timeout: float = 3.0) -> bool:
    try:
        with socket.create_connection(("localhost", port), timeout=timeout):
            return True
    except OSError:
        return False


def test_container_and_qemu_are_running() -> None:
    inspect = _docker(["inspect", "--format", "{{.State.Status}}", "komorebi-test"])
    assert inspect.returncode == 0, inspect.stderr
    assert inspect.stdout.strip() == "running"

    monitor = _docker(
        [
            "exec",
            "komorebi-test",
            "bash",
            "-c",
            'echo "info status" | nc -q1 localhost 7100',
        ]
    )
    assert monitor.returncode == 0, monitor.stderr
    assert "running" in monitor.stdout


def test_vm_ports_are_open() -> None:
    assert _port_open(8006), "VNC port 8006 is not reachable"
    assert _port_open(3389), "RDP port 3389 is not reachable"
