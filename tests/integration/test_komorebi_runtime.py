"""実機で動作中のkomorebi状態を検証する。"""

from __future__ import annotations

import json
import shutil
import subprocess


def _komorebic(args: list[str]) -> object:
    executable = shutil.which("komorebic")
    assert executable is not None, "komorebic command is not installed or not on PATH"
    result = subprocess.run(
        [executable, *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def test_komorebi_detects_at_least_one_monitor() -> None:
    monitors = _komorebic(["monitor-information"])

    assert isinstance(monitors, list)
    assert len(monitors) >= 1


def test_each_monitor_has_one_orientation_based_workspace() -> None:
    state = _komorebic(["state"])

    assert isinstance(state, dict)
    monitors = state["monitors"]["elements"]
    assert len(monitors) >= 1
    for monitor in monitors:
        width = monitor["size"]["right"]
        height = monitor["size"]["bottom"]
        assert width > 0
        assert height > 0
        expected_layout = "Columns" if width > height else "Rows"
        workspaces = monitor["workspaces"]["elements"]
        assert len(workspaces) == 1
        assert workspaces[0]["layout"] == {"Default": expected_layout}


def test_office_application_rules_are_loaded() -> None:
    state = _komorebic(["global-state"])

    assert isinstance(state, dict)
    for executable in ("EXCEL.EXE", "POWERPNT.EXE", "WINWORD.EXE"):
        assert {
            "kind": "Exe",
            "id": executable,
            "matching_strategy": "Equals",
        } in state["layered_whitelist"]
    assert {
        "kind": "Class",
        "id": "_WwB",
        "matching_strategy": "Legacy",
    } in state["ignore_identifiers"]
