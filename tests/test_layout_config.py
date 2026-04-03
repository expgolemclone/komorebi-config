"""Tests for komorebi.json layout configuration."""

import json
from pathlib import Path

CONFIG = Path(__file__).resolve().parent.parent / "komorebi.json"

VALID_LAYOUTS = {
    "BSP",
    "Columns",
    "Rows",
    "VerticalStack",
    "HorizontalStack",
    "UltrawideVerticalStack",
    "Grid",
    "RightMainVerticalStack",
}


def _load_config():
    with open(CONFIG, encoding="utf-8") as f:
        return json.load(f)


def _all_workspaces(cfg):
    return [
        ws
        for m in cfg.get("monitors", [])
        for ws in m.get("workspaces", [])
    ]


def test_valid_json():
    cfg = _load_config()
    assert isinstance(cfg, dict)


def test_all_workspaces_have_layout():
    cfg = _load_config()
    for ws in _all_workspaces(cfg):
        assert "layout" in ws, f"Workspace {ws.get('name')} missing layout"


def test_all_layouts_are_valid():
    cfg = _load_config()
    for ws in _all_workspaces(cfg):
        layout = ws.get("layout")
        assert layout in VALID_LAYOUTS, f"Invalid layout: {layout}"


def test_current_layout_is_columns():
    cfg = _load_config()
    for ws in _all_workspaces(cfg):
        assert ws.get("layout") == "Columns", (
            f"Workspace {ws.get('name')} uses {ws.get('layout')}, expected Columns"
        )
