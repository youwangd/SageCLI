#!/bin/bash
# tests/coverage.sh — Report which sage commands have test coverage
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SAGE="$REPO_ROOT/sage"

# Extract all cmd_* function names → command names
commands=()
while IFS= read -r c; do commands+=("$c"); done < <(grep -o '^cmd_[a-z_]*' "$SAGE" | sed 's/^cmd_//' | sort -u)

# Extract all commands tested in bats files
tested=()
while IFS= read -r t; do tested+=("$t"); done < <(grep -oE '(sage|"\$SAGE") [a-z_]+' "$REPO_ROOT"/tests/*.bats | grep -oE '[a-z_]+$' | sort -u)

total=${#commands[@]}
covered=0
untested=()

for cmd in "${commands[@]}"; do
  if printf '%s\n' "${tested[@]}" | grep -qx "$cmd" 2>/dev/null; then
    ((covered++)) || true
  else
    untested+=("$cmd")
  fi
done

pct=$((covered * 100 / total))
echo "Coverage: ${pct}% (${covered}/${total})"

if [ ${#untested[@]} -gt 0 ]; then
  echo "Untested: ${untested[*]}"
fi
