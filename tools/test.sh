#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --editor --import --quit
for test in tests/*_test.gd; do
  echo "=== $test ==="
  log="$(mktemp)"
  if ! timeout 30 "$GODOT" --headless --path . --script "$test" 2>&1 | tee "$log"; then
    rm -f "$log"
    exit 1
  fi
  if grep -Eq 'SCRIPT ERROR|ERROR:|Assertion failed' "$log"; then
    rm -f "$log"
    exit 1
  fi
  rm -f "$log"
done
