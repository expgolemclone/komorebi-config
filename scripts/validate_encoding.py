"""git変更ファイルのUTF-8エンコーディングとLF改行を検証する。

Claude Code の Stop hook として使用。
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def _git_modified_files() -> list[str]:
    unstaged: subprocess.CompletedProcess[str] = subprocess.run(
        ["git", "diff", "--name-only", "HEAD"],
        capture_output=True,
        text=True,
    )
    staged: subprocess.CompletedProcess[str] = subprocess.run(
        ["git", "diff", "--cached", "--name-only"],
        capture_output=True,
        text=True,
    )
    combined: str = unstaged.stdout + staged.stdout
    return sorted(set(line for line in combined.splitlines() if line))


def _is_binary(path: Path) -> bool:
    try:
        chunk: bytes = path.read_bytes()[:8192]
        return b"\x00" in chunk
    except OSError:
        return True


def _check_encoding(path: Path) -> str | None:
    try:
        path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return f"ENCODING: {path} is not UTF-8"
    return None


def _check_line_endings(path: Path) -> str | None:
    raw: bytes = path.read_bytes()
    if b"\r\n" in raw:
        return f"CRLF: {path} has CRLF line endings (expected LF)"
    return None


def main() -> int:
    files: list[str] = _git_modified_files()
    if not files:
        return 0

    errors: list[str] = []
    for name in files:
        path: Path = Path(name)
        if not path.is_file() or _is_binary(path):
            continue

        encoding_error: str | None = _check_encoding(path)
        if encoding_error:
            errors.append(encoding_error)

        line_ending_error: str | None = _check_line_endings(path)
        if line_ending_error:
            errors.append(line_ending_error)

    if errors:
        print("=== Encoding/Line-ending check FAILED ===")
        for error in errors:
            print(f"  {error}")
        return 1

    print("Encoding check passed: all modified files are UTF-8 with LF.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
