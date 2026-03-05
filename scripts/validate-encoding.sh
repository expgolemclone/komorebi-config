#!/bin/bash
# Check that git-modified files are UTF-8 encoded with LF line endings.
# Used as a Claude Code stop hook.

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

# Get files modified/staged in git (tracked text files only)
files=$(git diff --name-only HEAD 2>/dev/null; git diff --cached --name-only 2>/dev/null)
files=$(echo "$files" | sort -u | grep -v '^$')

if [ -z "$files" ]; then
  exit 0
fi

errors=()

while IFS= read -r f; do
  [ -f "$f" ] || continue

  # Skip binary files
  if file --mime-encoding "$f" 2>/dev/null | grep -q 'binary'; then
    continue
  fi

  # Check encoding is UTF-8 (or ascii, which is valid UTF-8)
  encoding=$(file --mime-encoding "$f" 2>/dev/null | sed 's/.*: //')
  if [[ "$encoding" != "utf-8" && "$encoding" != "us-ascii" ]]; then
    errors+=("ENCODING: $f is $encoding (expected utf-8)")
  fi

  # Check for CRLF line endings (cat -A shows ^M$ at end of CRLF lines)
  if cat -A "$f" | grep -q '\^M\$'; then
    errors+=("CRLF: $f has CRLF line endings (expected LF)")
  fi
done <<< "$files"

if [ ${#errors[@]} -gt 0 ]; then
  echo "=== Encoding/Line-ending check FAILED ==="
  for e in "${errors[@]}"; do
    echo "  $e"
  done
  exit 1
fi

echo "Encoding check passed: all modified files are UTF-8 with LF."
exit 0
