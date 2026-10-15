"""jjまたはGitで管理されているtext fileのUTF-8 encodingとLF改行を検証する。"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def _jj_command(args: list[str]) -> list[str]:
    if os.name == "nt":
        return [os.environ["COMSPEC"], "/d", "/c", "jj", *args]
    return ["jj", *args]


def _run_jj(args: list[str], cwd: Path | None = None) -> str:
    try:
        result = subprocess.run(
            _jj_command(args),
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except FileNotFoundError as error:
        raise RuntimeError("jj command is not installed or not on PATH") from error
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(f"jj {' '.join(args)} failed: {detail}")
    return result.stdout


def _run_git(args: list[str], cwd: Path | None = None) -> str:
    try:
        result = subprocess.run(
            ["git", *args],
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except FileNotFoundError as error:
        raise RuntimeError("git command is not installed or not on PATH") from error
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(f"git {' '.join(args)} failed: {detail}")
    return result.stdout


def _repository() -> tuple[Path, str]:
    try:
        return Path(_run_jj(["root"]).strip()), "jj"
    except RuntimeError as jj_error:
        try:
            root = Path(_run_git(["rev-parse", "--show-toplevel"]).strip())
            return root, "git"
        except RuntimeError as git_error:
            raise RuntimeError(f"{jj_error}; {git_error}") from git_error


def _tracked_files(root: Path, repository_type: str) -> list[Path]:
    if repository_type == "jj":
        output = _run_jj(["file", "list", "-r", "@"], cwd=root)
    else:
        output = _run_git(["ls-files"], cwd=root)
    return [root / name for name in output.splitlines() if name]


def _is_binary(path: Path) -> bool:
    with path.open("rb") as file:
        return b"\x00" in file.read(8192)


def _check_encoding(path: Path, root: Path) -> str | None:
    try:
        path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return f"ENCODING: {path.relative_to(root)} is not UTF-8"
    return None


def _check_line_endings(path: Path, root: Path) -> str | None:
    if b"\r\n" in path.read_bytes():
        return f"CRLF: {path.relative_to(root)} has CRLF line endings (expected LF)"
    return None


def main() -> int:
    try:
        root, repository_type = _repository()
        files = _tracked_files(root, repository_type)
    except RuntimeError as error:
        print(f"REPOSITORY: {error}")
        return 1

    errors: list[str] = []
    for path in files:
        if not path.is_file():
            continue

        try:
            if _is_binary(path):
                continue
        except OSError as error:
            errors.append(f"READ: {path.relative_to(root)}: {error}")
            continue

        encoding_error = _check_encoding(path, root)
        if encoding_error:
            errors.append(encoding_error)

        line_ending_error = _check_line_endings(path, root)
        if line_ending_error:
            errors.append(line_ending_error)

    if errors:
        print("=== Encoding/Line-ending check FAILED ===")
        for error in errors:
            print(f"  {error}")
        return 1

    print("Encoding check passed: all tracked text files are UTF-8 with LF.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
