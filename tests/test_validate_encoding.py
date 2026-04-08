"""validate_encoding.py のテスト。

一時gitリポジトリを作成し、エンコーディング・改行コード検証を確認する。
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT: Path = Path(__file__).resolve().parent.parent / "scripts" / "validate_encoding.py"


def _git(args: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=cwd,
        capture_output=True,
        text=True,
        check=True,
    )


def _init_repo(tmp_path: Path) -> Path:
    repo = tmp_path / "repo"
    repo.mkdir()
    _git(["init"], repo)
    _git(["config", "user.email", "test@test.com"], repo)
    _git(["config", "user.name", "test"], repo)
    _git(["config", "core.autocrlf", "false"], repo)
    init_file = repo / "init.txt"
    init_file.write_text("init\n", encoding="utf-8")
    _git(["add", "init.txt"], repo)
    _git(["commit", "-m", "init"], repo)
    return repo


def _run_script(cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT)],
        cwd=cwd,
        capture_output=True,
        text=True,
    )


def test_utf8_lf_passes(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    (repo / "good.txt").write_text("hello\nworld\n", encoding="utf-8", newline="\n")
    _git(["add", "good.txt"], repo)

    result = _run_script(repo)

    assert result.returncode == 0


def test_crlf_fails(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    (repo / "crlf.txt").write_bytes(b"hello\r\nworld\r\n")
    _git(["add", "crlf.txt"], repo)

    result = _run_script(repo)

    assert result.returncode == 1


def test_no_modified_files_passes(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)

    result = _run_script(repo)

    assert result.returncode == 0


def test_japanese_utf8_passes(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    (repo / "jp.txt").write_text("日本語テスト\n", encoding="utf-8", newline="\n")
    _git(["add", "jp.txt"], repo)

    result = _run_script(repo)

    assert result.returncode == 0


def test_mixed_files_fail(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    (repo / "a.txt").write_text("good\n", encoding="utf-8", newline="\n")
    (repo / "b.txt").write_bytes(b"bad\r\n")
    _git(["add", "a.txt", "b.txt"], repo)

    result = _run_script(repo)

    assert result.returncode == 1
