#!/usr/bin/env bats
# tests/sage-ls-sort.bats — ls --sort sorts agents by field

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-ls-sort-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  "$SAGE" create alpha --runtime bash >/dev/null 2>&1
  "$SAGE" create beta --runtime claude-code >/dev/null 2>&1
  "$SAGE" create gamma --runtime bash >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "ls --sort runtime groups agents by runtime" {
  local out
  out=$("$SAGE" ls --sort runtime)
  # bash agents (alpha, gamma) should come before claude-code (beta)
  local first third
  first=$(echo "$out" | sed -n '1p')
  third=$(echo "$out" | sed -n '3p')
  [[ "$first" == "alpha" || "$first" == "gamma" ]]
  [[ "$third" == "beta" ]]
}

@test "ls --sort name is default alphabetical" {
  local out
  out=$("$SAGE" ls --sort name)
  [[ "$(echo "$out" | sed -n '1p')" == "alpha" ]]
  [[ "$(echo "$out" | sed -n '2p')" == "beta" ]]
  [[ "$(echo "$out" | sed -n '3p')" == "gamma" ]]
}

@test "ls --sort works with -l flag" {
  run "$SAGE" ls -l --sort runtime
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"NAME"* ]]
  [[ "$output" == *"alpha"* ]]
}

@test "ls --sort rejects invalid field" {
  run "$SAGE" ls --sort invalid
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"invalid sort field"* ]]
}
