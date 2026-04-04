"""komorebi が Windows VM 内で動作していることを検証するテスト。

Docker コンテナの状態、ポートの疎通、QEMU VM のステータスを確認する。
"""

from __future__ import annotations

import socket
import subprocess


def _docker_inspect(fmt: str) -> str:
    result: subprocess.CompletedProcess[str] = subprocess.run(
        ["docker", "inspect", "--format", fmt, "komorebi-test"],
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def _qemu_monitor_command(cmd: str) -> str:
    result: subprocess.CompletedProcess[bytes] = subprocess.run(
        [
            "docker", "exec", "komorebi-test",
            "bash", "-c", f'echo "{cmd}" | nc -q1 localhost 7100 2>/dev/null',
        ],
        capture_output=True,
        timeout=10,
    )
    return result.stdout.decode("utf-8", errors="replace")


def _port_open(port: int, timeout: float = 3.0) -> bool:
    try:
        with socket.create_connection(("localhost", port), timeout=timeout):
            return True
    except OSError:
        return False


def test_container_running() -> None:
    # Arrange
    expected: str = "running"

    # Act
    status: str = _docker_inspect("{{.State.Status}}")

    # Assert
    assert status == expected, f"コンテナが running ではない: {status}"


def test_vnc_port_open() -> None:
    # Act
    reachable: bool = _port_open(8006)

    # Assert
    assert reachable, "VNC ポート 8006 に接続できない"


def test_rdp_port_open() -> None:
    # Act
    reachable: bool = _port_open(3389)

    # Assert
    assert reachable, "RDP ポート 3389 に接続できない"


def test_qemu_vm_running() -> None:
    # Act
    output: str = _qemu_monitor_command("info status")

    # Assert
    assert "running" in output, f"QEMU VM が running ではない: {output}"
