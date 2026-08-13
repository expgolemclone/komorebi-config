"""restart.ps1 の設定ポータビリティを検証するテスト。"""

from __future__ import annotations

import re
from pathlib import Path

RESTART_SCRIPT: Path = Path(__file__).resolve().parent.parent / "scripts" / "restart.ps1"
DISTRIBUTE_SCRIPT: Path = (
    Path(__file__).resolve().parent.parent / "scripts" / "distribute-windows.ps1"
)


def _read_script() -> str:
    return RESTART_SCRIPT.read_text(encoding="utf-8")


def test_no_hardcoded_user_path() -> None:
    # Arrange
    content: str = _read_script()
    hardcoded_pattern: re.Pattern[str] = re.compile(
        r"C:\\Users\\[^$\\]+\\", re.IGNORECASE
    )

    # Act
    matches: list[str] = hardcoded_pattern.findall(content)

    # Assert
    assert matches == [], f"ハードコードされたユーザーパスが存在: {matches}"


def test_uses_env_userprofile() -> None:
    # Arrange
    content: str = _read_script()

    # Act
    uses_userprofile: bool = "$env:USERPROFILE" in content

    # Assert
    assert uses_userprofile, "$env:USERPROFILE が使用されていない"


def test_contains_required_process_names() -> None:
    # Arrange
    content: str = _read_script()
    required_processes: list[str] = ["komorebi", "komorebi-bar", "whkd"]

    # Act & Assert
    for process in required_processes:
        assert process in content, f"必要なプロセス名 '{process}' が見つからない"


def test_auto_distribution_script_is_removed() -> None:
    assert not DISTRIBUTE_SCRIPT.exists(), (
        "意図しないフォーカス中ウィンドウの移動を防ぐため、"
        "distribute-windows.ps1 は削除されている必要がある"
    )


def test_restart_does_not_reference_auto_distribution() -> None:
    content: str = _read_script()

    assert "distribute-windows" not in content
    assert "subscribe-pipe" not in content
