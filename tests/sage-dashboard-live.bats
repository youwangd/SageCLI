#!/usr/bin/env bats

setup() {
  export SAGE_HOME=$(mktemp -d)
  export AGENTS_DIR="$SAGE_HOME/agents"
  export PLANS_DIR="$SAGE_HOME/plans"
  mkdir -p "$AGENTS_DIR" "$PLANS_DIR"
  SAGE="$BATS_TEST_DIRNAME/../sage"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

_create_agent() {
  local name="$1" runtime="${2:-bash}"
  mkdir -p "$AGENTS_DIR/$name"
  echo "{\"runtime\":\"$runtime\"}" > "$AGENTS_DIR/$name/runtime.json"
}

@test "dashboard --live flag is accepted" {
  _create_agent "bot1"
  # --live with non-TTY stdin should exit gracefully (print once and exit)
  run "$SAGE" dashboard --live </dev/null
  [[ "$status" -eq 0 ]]
}

@test "dashboard --live shows keybinding help" {
  _create_agent "bot1"
  run "$SAGE" dashboard --live </dev/null
  [[ "$output" == *"r=restart"* ]]
  [[ "$output" == *"s=stop"* ]]
  [[ "$output" == *"l=logs"* ]]
  [[ "$output" == *"q=quit"* ]]
}

@test "dashboard --live shows agent list" {
  _create_agent "alpha" "claude-code"
  _create_agent "beta" "bash"
  run "$SAGE" dashboard --live </dev/null
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"beta"* ]]
}

@test "dashboard --live shows selection indicator" {
  _create_agent "bot1"
  run "$SAGE" dashboard --live </dev/null
  [[ "$output" == *">"* ]]
}

@test "dashboard --live with no agents shows empty message" {
  run "$SAGE" dashboard --live </dev/null
  [[ "$output" == *"No agents"* ]]
  [[ "$status" -eq 0 ]]
}

@test "dashboard --live and --json are mutually exclusive" {
  run "$SAGE" dashboard --live --json
  [[ "$status" -ne 0 ]]
}
