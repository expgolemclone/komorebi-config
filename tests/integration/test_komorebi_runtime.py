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
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def test_komorebi_detects_at_least_one_monitor() -> None:
    monitors = _komorebic(["monitor-information"])

    assert isinstance(monitors, list)
    assert len(monitors) >= 1


def test_each_monitor_has_one_rows_workspace() -> None:
    state = _komorebic(["state"])

    assert isinstance(state, dict)
    monitors = state["monitors"]["elements"]
    assert len(monitors) >= 1
    for monitor in monitors:
        workspaces = monitor["workspaces"]["elements"]
        assert len(workspaces) == 1
        assert workspaces[0]["layout"] == {"Default": "Rows"}
