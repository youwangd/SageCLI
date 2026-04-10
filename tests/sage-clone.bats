#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-clone-test-$$"
  "$SAGE" init 2>/dev/null
  "$SAGE" create original --runtime bash 2>/dev/null
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "sage clone copies agent config" {
  run "$SAGE" clone original copy1
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/agents/copy1/runtime.json" ]
}

@test "sage clone preserves runtime type" {
  run "$SAGE" clone original copy1
  [ "$status" -eq 0 ]
  local rt
  rt=$(jq -r '.runtime' "$SAGE_HOME/agents/copy1/runtime.json")
  [ "$rt" = "bash" ]
}

@test "sage clone updates agent name in runtime.json" {
  run "$SAGE" clone original copy1
  [ "$status" -eq 0 ]
  local name
  name=$(jq -r '.name' "$SAGE_HOME/agents/copy1/runtime.json")
  [ "$name" = "copy1" ]
}

@test "sage clone creates fresh inbox/state/replies dirs" {
  echo "test" > "$SAGE_HOME/agents/original/inbox/msg.json"
  run "$SAGE" clone original copy1
  [ "$status" -eq 0 ]
  [ -d "$SAGE_HOME/agents/copy1/inbox" ]
  [ ! -f "$SAGE_HOME/agents/copy1/inbox/msg.json" ]
}

@test "sage clone copies system_prompt if present" {
  echo "You are a helpful agent" > "$SAGE_HOME/agents/original/system_prompt"
  run "$SAGE" clone original copy1
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/agents/copy1/system_prompt" ]
  run cat "$SAGE_HOME/agents/copy1/system_prompt"
  [[ "$output" == *"helpful agent"* ]]
}

@test "sage clone copies mcp.json if present" {
  echo '{"mcpServers":{}}' > "$SAGE_HOME/agents/original/mcp.json"
  run "$SAGE" clone original copy1
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/agents/copy1/mcp.json" ]
}

@test "sage clone fails if source doesn't exist" {
  run "$SAGE" clone nonexistent copy1
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "sage clone fails if dest already exists" {
  "$SAGE" create existing --runtime bash 2>/dev/null
  run "$SAGE" clone original existing
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "sage clone requires both arguments" {
  run "$SAGE" clone original
  [ "$status" -ne 0 ]
}

@test "sage help includes clone command" {
  run "$SAGE" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"clone"* ]]
}
