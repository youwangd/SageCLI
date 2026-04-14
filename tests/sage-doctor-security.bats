#!/usr/bin/env bats

setup() {
  export SAGE_HOME="$(mktemp -d)"
  SAGE="$BATS_TEST_DIRNAME/../sage"
  "$SAGE" init --force >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

_make_agent() {
  local name="$1"
  shift
  mkdir -p "$SAGE_HOME/agents/$name"
  local json='{"runtime":"bash"'
  while [[ $# -gt 0 ]]; do
    json="$json,\"$1\":$2"
    shift 2
  done
  json="$json}"
  echo "$json" > "$SAGE_HOME/agents/$name/runtime.json"
}

@test "doctor --security: warns agent with no guardrails" {
  _make_agent "unsafe"
  run "$SAGE" doctor --security
  [[ "$output" == *"unsafe"* ]]
  [[ "$output" == *"no guardrails"* ]] || [[ "$output" == *"none"* ]]
}

@test "doctor --security: shows agent with full guardrails as ok" {
  _make_agent "safe" timeout_seconds 300 max_turns 20
  run "$SAGE" doctor --security
  [[ "$output" == *"safe"* ]]
  [[ "$output" == *"✓"* ]] || [[ "$output" == *"ok"* ]] || [[ "$output" == *"guarded"* ]]
}

@test "doctor --security: warns agent with partial guardrails" {
  _make_agent "partial" timeout_seconds 300
  run "$SAGE" doctor --security
  [[ "$output" == *"partial"* ]]
  [[ "$output" == *"max-turns"* ]] || [[ "$output" == *"missing"* ]]
}

@test "doctor --security: shows summary line" {
  _make_agent "a1" timeout_seconds 60 max_turns 10
  _make_agent "a2"
  run "$SAGE" doctor --security
  [[ "$output" == *"2 agent"* ]]
}

@test "doctor --security: exits 1 when agent has no guardrails" {
  _make_agent "risky"
  run "$SAGE" doctor --security
  [ "$status" -ne 0 ]
}
