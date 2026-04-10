"""display_index_preferences のシリアル番号が実機と一致することを検証するテスト。"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

CONFIG: Path = Path(__file__).resolve().parent.parent / "komorebi.json"
KOMOREBIC: str = r"C:\Program Files\komorebi\bin\komorebic.exe"


def _load_config() -> dict:
    with open(CONFIG, encoding="utf-8") as f:
        return json.load(f)


def _get_state() -> dict:
    result: subprocess.CompletedProcess[str] = subprocess.run(
        [KOMOREBIC, "state"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    return json.loads(result.stdout)


def _actual_serials(state: dict) -> list[str]:
    return [m["serial_number_id"] for m in state["monitors"]["elements"]]


def _config_serials(cfg: dict) -> dict[int, str]:
    return {
        int(k): v
        for k, v in cfg.get("display_index_preferences", {}).items()
    }


def test_display_index_preferences_count_matches_monitors() -> None:
    # Arrange
    cfg: dict = _load_config()
    state: dict = _get_state()

    # Act
    pref_count: int = len(_config_serials(cfg))
    monitor_count: int = len(state["monitors"]["elements"])

    # Assert
    assert pref_count == monitor_count, (
        f"display_index_preferences has {pref_count} entries "
        f"but {monitor_count} monitors detected"
    )


def test_monitors_count_matches_config() -> None:
    # Arrange
    cfg: dict = _load_config()
    state: dict = _get_state()

    # Act
    config_count: int = len(cfg.get("monitors", []))
    actual_count: int = len(state["monitors"]["elements"])

    # Assert
    assert config_count == actual_count, (
        f"config defines {config_count} monitors "
        f"but {actual_count} monitors detected"
    )


def test_each_serial_exists_in_actual_monitors() -> None:
    # Arrange
    cfg: dict = _load_config()
    state: dict = _get_state()
    serials: list[str] = _actual_serials(state)

    # Act & Assert
    for idx, serial in _config_serials(cfg).items():
        assert serial in serials, (
            f"index {idx} serial '{serial}' not found "
            f"in actual monitors: {serials}"
        )
