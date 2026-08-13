"""komorebi, bar, whkdの静的設定を検証する。"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def _load_json(name: str) -> dict:
    with (ROOT / name).open(encoding="utf-8") as file:
        return json.load(file)


def test_komorebi_uses_automatic_monitor_detection() -> None:
    config = _load_json("komorebi.json")

    assert "monitors" not in config
    assert "display_index_preferences" not in config


def test_padding_and_border_configuration() -> None:
    config = _load_json("komorebi.json")

    assert config["default_workspace_padding"] == 0
    assert config["default_container_padding"] == 0
    assert config["border"] is True
    assert config["border_width"] == 8
    assert config["border_implementation"] == "Windows"
    for kind in ("single", "stack", "monocle", "floating"):
        assert config["border_colours"][kind] == "#00FFFF"


def test_mouse_follows_focus_is_disabled() -> None:
    assert _load_json("komorebi.json")["mouse_follows_focus"] is False


def test_all_configured_bar_widgets_are_enabled() -> None:
    config = _load_json("komorebi.bar.json")

    def assert_enabled(value: object, path: str) -> None:
        if isinstance(value, dict):
            if "enable" in value:
                assert value["enable"] is True, f"{path}.enable is false"
            for key, child in value.items():
                assert_enabled(child, f"{path}.{key}")
        elif isinstance(value, list):
            for index, child in enumerate(value):
                assert_enabled(child, f"{path}[{index}]")

    assert_enabled(config["left_widgets"], "left_widgets")
    assert_enabled(config["right_widgets"], "right_widgets")


def test_whkd_uses_only_workspace_zero() -> None:
    whkdrc = (ROOT / "whkdrc").read_text(encoding="utf-8")
    focus_indexes = re.findall(r"komorebic focus-workspace\s+(\d+)", whkdrc)
    move_indexes = re.findall(r"komorebic move-to-workspace\s+(\d+)", whkdrc)

    assert focus_indexes == ["0"]
    assert move_indexes == ["0"]


def test_whkd_replaces_static_configuration() -> None:
    whkdrc = (ROOT / "whkdrc").read_text(encoding="utf-8")

    assert "reload-configuration" not in whkdrc
    assert (
        'komorebic replace-configuration '
        '"%KOMOREBI_CONFIG_HOME%\\komorebi.json"'
    ) in whkdrc


def test_focus_bindings_move_cursor_for_all_directions() -> None:
    whkdrc = (ROOT / "whkdrc").read_text(encoding="utf-8")

    for direction in ("left", "down", "up", "right"):
        pattern = rf"komorebic focus {direction}.*move-cursor-bottom-center"
        assert re.search(pattern, whkdrc)
