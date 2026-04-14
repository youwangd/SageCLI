#!/usr/bin/env bats
# tests/sage-grep-portability.bats — verify no grep -P (Perl regex) in sage

setup() {
  export SAGE="$BATS_TEST_DIRNAME/../sage"
}

@test "sage has no grep -P calls (macOS compat)" {
  # BSD grep on macOS lacks -P flag entirely
  count=$(grep -c 'grep -[a-zA-Z]*P' "$SAGE" || true)
  [ "$count" -eq 0 ]
}

@test "sage status runs without error" {
  export SAGE_HOME=$(mktemp -d)
  mkdir -p "$SAGE_HOME/agents" "$SAGE_HOME/logs"
  run "$SAGE" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"SAGE"* ]]
  rm -rf "$SAGE_HOME"
}

@test "sage status shows agent table header" {
  export SAGE_HOME=$(mktemp -d)
  mkdir -p "$SAGE_HOME/agents" "$SAGE_HOME/logs"
  run "$SAGE" status
  [[ "$output" == *"AGENT"* ]]
  [[ "$output" == *"RUNTIME"* ]]
  rm -rf "$SAGE_HOME"
}

@test "sage status shows created agent" {
  export SAGE_HOME=$(mktemp -d)
  "$SAGE" init --force 2>/dev/null || true
  "$SAGE" create testbot 2>/dev/null || true
  run "$SAGE" status
  [[ "$output" == *"testbot"* ]]
  rm -rf "$SAGE_HOME"
}
