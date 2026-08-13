"""Generate PowerShell setup commands for komorebi test VM.

Run with --dry-run to print the commands without executing.
Run without flags inside the Windows VM to execute via PowerShell.
"""

from __future__ import annotations

import argparse
import subprocess
import sys

SHARED_FOLDER: str = r"\\host.lan\Data"

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
    return rf"""$ErrorActionPreference = "Stop"
$configDir = Join-Path $env:USERPROFILE ".config\komorebi"
$sharedPath = "{SHARED_FOLDER}"

Write-Host "=== komorebi test environment setup ===" -ForegroundColor Cyan

# Install PowerShell, komorebi, and whkd
Write-Host "[1/3] Installing PowerShell, komorebi, and whkd..." -ForegroundColor Yellow
winget install --id Microsoft.PowerShell --exact --accept-package-agreements --accept-source-agreements
winget install --id LGUG2Z.komorebi --exact --accept-package-agreements --accept-source-agreements
winget install --id LGUG2Z.whkd --exact --accept-package-agreements --accept-source-agreements
$env:Path = @(
    [Environment]::GetEnvironmentVariable("Path", "Machine"),
    [Environment]::GetEnvironmentVariable("Path", "User")
) -join ";"

# Verify the shared folder
Write-Host "[2/3] Copying config files..." -ForegroundColor Yellow
if (-not (Test-Path -LiteralPath $sharedPath -PathType Container)) {{
    Write-Host "FAIL: shared folder not found: $sharedPath" -ForegroundColor Red
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
pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $configDir "scripts\restart.ps1")

Write-Host "=== Setup complete ===" -ForegroundColor Cyan
Write-Host "Run: cd $configDir && pwsh -NoProfile -File tests\integration\windows\test-restart.ps1"
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
