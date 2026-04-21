#!/usr/bin/env bats
# tests/sage-status-json.bats — sage status --json emits machine-readable system state

setup() {
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  export SAGE_HOME="$BATS_TEST_TMPDIR/sage-status-$$"
  sage init --quiet 2>/dev/null || true
}

teardown() {
  rm -rf "$SAGE_HOME" 2>/dev/null || true
}

@test "status --json emits valid JSON with empty agents array when no agents" {
  run sage status --json
  [ "$status" -eq 0 ]
  # must be valid JSON
  echo "$output" | jq . >/dev/null
  # agents key exists and is empty array
  local n; n=$(echo "$output" | jq '.agents | length')
  [ "$n" -eq 0 ]
  # sage_home key present
  echo "$output" | jq -e '.sage_home' >/dev/null
  # tmux object present
  echo "$output" | jq -e '.tmux' >/dev/null
}

@test "status --json lists created agents with expected fields" {
  sage create alpha --runtime bash 2>/dev/null || true
  sage create beta --runtime bash 2>/dev/null || true
  run sage status --json
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null
  local names
  names=$(echo "$output" | jq -r '.agents[].name' | sort | paste -sd, -)
  [ "$names" = "alpha,beta" ]
  # each agent has required fields
  echo "$output" | jq -e '.agents[0] | .name and .runtime and .status' >/dev/null
}

@test "status --json does not emit ANSI color codes or banner text" {
  sage create gamma --runtime bash 2>/dev/null || true
  run sage status --json
  [ "$status" -eq 0 ]
  # no escape char
  [[ "$output" != *$'\033'* ]]
  # no pretty banner
  [[ "$output" != *"SAGE — Simple Agent Engine"* ]]
}
