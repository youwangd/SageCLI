#!/usr/bin/env bats
# tests/sage-doctor-json.bats — doctor --json machine-readable output

setup() {
  export SAGE_HOME=$(mktemp -d)
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "doctor --json outputs valid JSON with checks array" {
  run sage doctor --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.checks' >/dev/null
  echo "$output" | jq -e '.summary' >/dev/null
}

@test "doctor --json checks have label, status, message fields" {
  run sage doctor --json
  [ "$status" -eq 0 ]
  local first
  first=$(echo "$output" | jq -r '.checks[0].label')
  [ -n "$first" ] && [ "$first" != "null" ]
  echo "$output" | jq -e '.checks[0].status' >/dev/null
  echo "$output" | jq -e '.checks[0].message' >/dev/null
}

@test "doctor --json summary has pass/warn/fail/total counts" {
  run sage doctor --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.summary.pass >= 0' >/dev/null
  echo "$output" | jq -e '.summary.warn >= 0' >/dev/null
  echo "$output" | jq -e '.summary.fail >= 0' >/dev/null
  echo "$output" | jq -e '.summary.total > 0' >/dev/null
}

@test "doctor --all --json includes all check categories" {
  run sage doctor --all --json
  local labels
  labels=$(echo "$output" | jq -r '.checks[].label' | sort -u)
  # Should have basic checks (bash, jq, tmux) at minimum
  echo "$labels" | grep -qi "bash"
  echo "$labels" | grep -qi "jq"
}

@test "doctor --security --json outputs valid JSON" {
  run sage doctor --security --json
  echo "$output" | jq -e '.checks' >/dev/null
  echo "$output" | jq -e '.summary' >/dev/null
}
