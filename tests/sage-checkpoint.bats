#!/usr/bin/env bats

setup() {
  export SAGE_HOME=$(mktemp -d)
  export AGENTS_DIR="$SAGE_HOME/agents"
  mkdir -p "$AGENTS_DIR" "$SAGE_HOME/checkpoints"
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

# --- checkpoint command ---

@test "checkpoint saves agent state to JSON file" {
  _create_agent "worker1" "claude-code"
  run "$SAGE" checkpoint worker1
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/checkpoints/worker1.json" ]
}

@test "checkpoint captures runtime from agent config" {
  _create_agent "worker1" "gemini-cli"
  "$SAGE" checkpoint worker1
  run jq -r '.runtime' "$SAGE_HOME/checkpoints/worker1.json"
  [ "$output" = "gemini-cli" ]
}

@test "checkpoint captures env vars" {
  _create_agent "worker1"
  mkdir -p "$AGENTS_DIR/worker1/env"
  echo "secret123" > "$AGENTS_DIR/worker1/env/API_KEY"
  "$SAGE" checkpoint worker1
  run jq -r '.env.API_KEY' "$SAGE_HOME/checkpoints/worker1.json"
  [ "$output" = "secret123" ]
}

@test "checkpoint captures mcp servers" {
  _create_agent "worker1"
  echo '{"servers":{"fs":{"command":"node","args":["server.js"]}}}' > "$AGENTS_DIR/worker1/mcp.json"
  "$SAGE" checkpoint worker1
  run jq -r '.mcp.servers.fs.command' "$SAGE_HOME/checkpoints/worker1.json"
  [ "$output" = "node" ]
}

@test "checkpoint --all saves all agents" {
  _create_agent "a1"
  _create_agent "a2"
  _create_agent "a3"
  run "$SAGE" checkpoint --all
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/checkpoints/a1.json" ]
  [ -f "$SAGE_HOME/checkpoints/a2.json" ]
  [ -f "$SAGE_HOME/checkpoints/a3.json" ]
}

@test "checkpoint fails for nonexistent agent" {
  run "$SAGE" checkpoint nosuchagent
  [ "$status" -ne 0 ]
}

# --- restore command ---

@test "restore recreates agent from checkpoint" {
  _create_agent "worker1" "codex"
  "$SAGE" checkpoint worker1
  rm -rf "$AGENTS_DIR/worker1"
  run "$SAGE" restore worker1
  [ "$status" -eq 0 ]
  [ -d "$AGENTS_DIR/worker1" ]
  run jq -r '.runtime' "$AGENTS_DIR/worker1/runtime.json"
  [ "$output" = "codex" ]
}

@test "restore recreates env vars from checkpoint" {
  _create_agent "worker1"
  mkdir -p "$AGENTS_DIR/worker1/env"
  echo "val1" > "$AGENTS_DIR/worker1/env/MY_VAR"
  "$SAGE" checkpoint worker1
  rm -rf "$AGENTS_DIR/worker1"
  "$SAGE" restore worker1
  [ -f "$AGENTS_DIR/worker1/env/MY_VAR" ]
  run cat "$AGENTS_DIR/worker1/env/MY_VAR"
  [ "$output" = "val1" ]
}

@test "restore recreates mcp config from checkpoint" {
  _create_agent "worker1"
  echo '{"servers":{}}' > "$AGENTS_DIR/worker1/mcp.json"
  "$SAGE" checkpoint worker1
  rm -rf "$AGENTS_DIR/worker1"
  "$SAGE" restore worker1
  [ -f "$AGENTS_DIR/worker1/mcp.json" ]
}

@test "restore --all restores all checkpointed agents" {
  _create_agent "x1" "bash"
  _create_agent "x2" "kiro"
  "$SAGE" checkpoint --all
  rm -rf "$AGENTS_DIR/x1" "$AGENTS_DIR/x2"
  run "$SAGE" restore --all
  [ "$status" -eq 0 ]
  [ -d "$AGENTS_DIR/x1" ]
  [ -d "$AGENTS_DIR/x2" ]
}

@test "restore fails with no checkpoint" {
  run "$SAGE" restore ghost
  [ "$status" -ne 0 ]
}

# --- checkpoint --ls (list existing checkpoints) ---

@test "checkpoint --ls shows empty when no checkpoints" {
  run "$SAGE" checkpoint --ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"no checkpoints"* ]]
}

@test "checkpoint --ls lists checkpoint names" {
  _create_agent "alpha" "claude-code"
  _create_agent "beta" "gemini-cli"
  "$SAGE" checkpoint alpha
  "$SAGE" checkpoint beta
  run "$SAGE" checkpoint --ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"beta"* ]]
}

@test "checkpoint --ls shows runtime for each checkpoint" {
  _create_agent "worker1" "codex"
  "$SAGE" checkpoint worker1
  run "$SAGE" checkpoint --ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex"* ]]
}

@test "checkpoint --ls --count returns 0 when no checkpoints" {
  run "$SAGE" checkpoint --ls --count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "checkpoint --ls --count returns integer count of saved checkpoints" {
  _create_agent "alpha"
  _create_agent "beta"
  _create_agent "gamma"
  "$SAGE" checkpoint alpha
  "$SAGE" checkpoint beta
  "$SAGE" checkpoint gamma
  run "$SAGE" checkpoint --ls --count
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "checkpoint --ls --count suppresses table output" {
  _create_agent "alpha" "claude-code"
  "$SAGE" checkpoint alpha
  run "$SAGE" checkpoint --ls --count
  [ "$status" -eq 0 ]
  [[ "$output" != *"claude-code"* ]]
  [[ "$output" != *"alpha"* ]]
}
