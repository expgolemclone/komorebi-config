"""restart.ps1 のミラー同期設定を検証するテスト。"""

from __future__ import annotations

import json
import os
from pathlib import Path

PROJECT_DIR: Path = Path(__file__).resolve().parent.parent
MIRROR_DIR: Path = Path(os.environ["USERPROFILE"]) / ".config" / "komorebi"
CONFIG_FILES: list[str] = ["komorebi.json", "komorebi.bar.json", "whkdrc"]


def test_mirror_dir_exists() -> None:
    # Assert
    assert MIRROR_DIR.is_dir(), f"ミラー先が存在しない: {MIRROR_DIR}"


def test_config_files_match() -> None:
    # Arrange & Act & Assert
    for name in CONFIG_FILES:
        src: Path = PROJECT_DIR / name
        dst: Path = MIRROR_DIR / name
        if not src.exists():
            continue
        assert dst.exists(), f"ミラー先に {name} が存在しない"
        src_content: str = src.read_text(encoding="utf-8")
        dst_content: str = dst.read_text(encoding="utf-8")
        assert src_content == dst_content, f"{name} の内容が一致しない"


def test_komorebi_json_serials_match() -> None:
    # Arrange
    src: Path = PROJECT_DIR / "komorebi.json"
    dst: Path = MIRROR_DIR / "komorebi.json"
    if not dst.exists():
        return

    # Act
    with open(src, encoding="utf-8") as f:
        src_prefs: dict[str, str] = json.load(f).get("display_index_preferences", {})
    with open(dst, encoding="utf-8") as f:
        dst_prefs: dict[str, str] = json.load(f).get("display_index_preferences", {})

    # Assert
    assert src_prefs == dst_prefs, (
        f"シリアル番号が不一致: src={src_prefs}, dst={dst_prefs}"
    )
