"""Generate PowerShell setup commands for komorebi test VM.

Run with --dry-run to print the commands without executing.
Run without flags inside the Windows VM to execute via PowerShell.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parent.parent

SHARED_FOLDER_CANDIDATES: list[str] = [
    r"\\host.lan\Data",
    r"C:\shared",
]

CONFIG_FILES: list[str] = [
    "komorebi.json",
    "komorebi.bar.json",
    "whkdrc",
]

CONFIG_DIRS: list[str] = [
    "scripts",
    "tests",
]


def _build_setup_commands() -> str:
    file_list: str = ", ".join(f'"{f}"' for f in CONFIG_FILES)
    dir_list: str = ", ".join(f'"{d}"' for d in CONFIG_DIRS)
    shared_paths: str = ", ".join(f'"{p}"' for p in SHARED_FOLDER_CANDIDATES)

    return rf"""$ErrorActionPreference = "Stop"
$configDir = Join-Path $env:USERPROFILE ".config\komorebi"

Write-Host "=== komorebi test environment setup ===" -ForegroundColor Cyan

# Install komorebi and whkd
Write-Host "[1/3] Installing komorebi and whkd..." -ForegroundColor Yellow
winget install LGUG2Z.komorebi --accept-package-agreements --accept-source-agreements
winget install LGUG2Z.whkd     --accept-package-agreements --accept-source-agreements

# Locate shared folder
Write-Host "[2/3] Copying config files..." -ForegroundColor Yellow
$sharedPath = $null
foreach ($candidate in @({shared_paths})) {{
    if (Test-Path $candidate) {{
        $sharedPath = $candidate
        break
    }}
}}
if (-not $sharedPath) {{
    Write-Host "FAIL: shared folder not found" -ForegroundColor Red
    exit 1
}}

New-Item -ItemType Directory -Path $configDir -Force | Out-Null

foreach ($file in @({file_list})) {{
    $src = Join-Path $sharedPath $file
    if (Test-Path $src) {{ Copy-Item $src $configDir -Force }}
}}
foreach ($dir in @({dir_list})) {{
    $src = Join-Path $sharedPath $dir
    if (Test-Path $src) {{ Copy-Item $src $configDir -Recurse -Force }}
}}

# Start komorebi
Write-Host "[3/3] Starting komorebi..." -ForegroundColor Yellow
powershell -ExecutionPolicy Bypass -File (Join-Path $configDir "scripts\restart.ps1")

Write-Host "=== Setup complete ===" -ForegroundColor Cyan
Write-Host "Run: cd $configDir && powershell -EP Bypass -File tests\test-restart.ps1"
"""


def dry_run() -> None:
    print(_build_setup_commands())


def execute() -> None:
    powershell: str = "powershell.exe"
    commands: str = _build_setup_commands()
    result: subprocess.CompletedProcess[str] = subprocess.run(
        [powershell, "-ExecutionPolicy", "Bypass", "-Command", commands],
        text=True,
    )
    sys.exit(result.returncode)


def main() -> None:
    parser: argparse.ArgumentParser = argparse.ArgumentParser(
        description="Setup komorebi test environment in Windows VM",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print PowerShell commands without executing",
    )
    args: argparse.Namespace = parser.parse_args()

    if args.dry_run:
        dry_run()
    else:
        execute()


if __name__ == "__main__":
    main()
