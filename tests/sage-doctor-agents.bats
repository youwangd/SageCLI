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
  local name="$1" runtime="$2"
  mkdir -p "$SAGE_HOME/agents/$name"
  echo "{\"runtime\":\"$runtime\"}" > "$SAGE_HOME/agents/$name/runtime.json"
}

@test "doctor --agents: shows bash agent as ok" {
  _make_agent "worker" "bash"
  run "$SAGE" doctor --agents
  [[ "$output" == *"worker"* ]]
  [[ "$output" == *"✓"* ]] || [[ "$output" == *"ok"* ]]
}

@test "doctor --agents: flags missing runtime binary" {
  _make_agent "broken" "nonexistent-runtime-xyz"
  run "$SAGE" doctor --agents
  [[ "$output" == *"broken"* ]]
  [[ "$output" == *"✗"* ]] || [[ "$output" == *"not found"* ]] || [[ "$output" == *"missing"* ]]
}

@test "doctor --agents: exits 1 when runtime missing" {
  _make_agent "broken" "nonexistent-runtime-xyz"
  run "$SAGE" doctor --agents
  [ "$status" -ne 0 ]
}

@test "doctor --agents: shows summary with agent count" {
  _make_agent "a1" "bash"
  _make_agent "a2" "bash"
  run "$SAGE" doctor --agents
  [[ "$output" == *"2 agent"* ]]
}

@test "doctor --agents: exits 0 when all runtimes found" {
  _make_agent "worker" "bash"
  run "$SAGE" doctor --agents
  [ "$status" -eq 0 ]
}
