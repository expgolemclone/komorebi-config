"""jjまたはGit repositoryに対するencoding検査を確認する。"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "validate_encoding.py"


def _jj_command(args: list[str]) -> list[str]:
    if os.name == "nt":
        return [os.environ["COMSPEC"], "/d", "/c", "jj", *args]
    return ["jj", *args]


def _init_repo(tmp_path: Path) -> Path:
    repo = tmp_path / "repo"
    repo.mkdir()
    result = subprocess.run(
        _jj_command(["git", "init", "."]),
        cwd=repo,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    return repo


def _run_script(cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT)],
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=10,
    )


@pytest.fixture(scope="module")
def jj_repo(tmp_path_factory: pytest.TempPathFactory) -> Path:
    return _init_repo(tmp_path_factory.mktemp("encoding-repo"))


@pytest.fixture(autouse=True)
def clean_jj_repo(jj_repo: Path) -> None:
    for path in jj_repo.iterdir():
        if path.name not in {".git", ".jj"}:
            assert path.is_file()
            path.unlink()


def test_utf8_lf_passes(jj_repo: Path) -> None:
    repo = jj_repo
    (repo / "good.txt").write_text("hello\nworld\n", encoding="utf-8", newline="\n")

    result = _run_script(repo)

    assert result.returncode == 0, result.stdout + result.stderr


def test_crlf_fails(jj_repo: Path) -> None:
    repo = jj_repo
    (repo / "crlf.txt").write_bytes(b"hello\r\nworld\r\n")

    result = _run_script(repo)

    assert result.returncode == 1
    assert "CRLF: crlf.txt" in result.stdout


def test_japanese_utf8_passes(jj_repo: Path) -> None:
    repo = jj_repo
    (repo / "jp.txt").write_text("日本語test\n", encoding="utf-8", newline="\n")

    result = _run_script(repo)

    assert result.returncode == 0, result.stdout + result.stderr


def test_binary_file_is_ignored(jj_repo: Path) -> None:
    repo = jj_repo
    (repo / "binary.bin").write_bytes(b"\x00\xff\r\n")

    result = _run_script(repo)

    assert result.returncode == 0, result.stdout + result.stderr


def test_git_repository_is_supported(tmp_path: Path) -> None:
    repo = tmp_path / "git-repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    (repo / "good.txt").write_text("Git repository\n", encoding="utf-8", newline="\n")
    subprocess.run(["git", "add", "good.txt"], cwd=repo, check=True)

    result = _run_script(repo)

    assert result.returncode == 0, result.stdout + result.stderr


def test_outside_repository_fails(tmp_path: Path) -> None:
    result = _run_script(tmp_path)

    assert result.returncode == 1
    assert "REPOSITORY:" in result.stdout
