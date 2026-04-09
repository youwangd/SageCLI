#!/usr/bin/env bats
# tests/sage-ci.bats — CI infrastructure tests

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "ci workflow file exists" {
  [[ -f "$REPO_ROOT/.github/workflows/ci.yml" ]]
}

@test "ci workflow references bats and shellcheck" {
  grep -q 'bats' "$REPO_ROOT/.github/workflows/ci.yml"
  grep -q 'shellcheck' "$REPO_ROOT/.github/workflows/ci.yml"
}

@test "shellcheck passes with no errors" {
  command -v shellcheck >/dev/null || skip "shellcheck not installed"
  shellcheck --severity=error "$REPO_ROOT/sage"
}
