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

# --- dashboard command ---

@test "dashboard shows header with agent count" {
  _create_agent "alpha"
  _create_agent "beta"
  run "$SAGE" dashboard
  [[ "$output" == *"2 agents"* ]]
}

@test "dashboard shows agent names" {
  _create_agent "mybot"
  run "$SAGE" dashboard
  [[ "$output" == *"mybot"* ]]
}

@test "dashboard shows runtime type" {
  _create_agent "coder" "acp"
  run "$SAGE" dashboard
  [[ "$output" == *"acp"* ]]
}

@test "dashboard shows stopped status for non-running agents" {
  _create_agent "idle-bot"
  run "$SAGE" dashboard
  [[ "$output" == *"stopped"* ]]
}

@test "dashboard with no agents shows empty message" {
  run "$SAGE" dashboard
  [[ "$output" == *"No agents"* ]]
}

@test "dashboard --json outputs valid JSON array" {
  _create_agent "a1" "bash"
  _create_agent "a2" "acp"
  run "$SAGE" dashboard --json
  echo "$output" | jq . >/dev/null 2>&1
}

@test "dashboard --json includes agent fields" {
  _create_agent "bot1" "acp"
  run "$SAGE" dashboard --json
  echo "$output" | jq -e '.[0].name == "bot1"'
  echo "$output" | jq -e '.[0].runtime == "acp"'
  echo "$output" | jq -e '.[0].status == "stopped"'
}

@test "dashboard --json with no agents returns empty array" {
  run "$SAGE" dashboard --json
  [[ "$output" == "[]" ]]
}
