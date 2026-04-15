#!/usr/bin/env bats

setup() {
  export SAGE_HOME="$(mktemp -d)"
  SAGE="$BATS_TEST_DIRNAME/../sage"
  "$SAGE" init --force >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "doctor --mcp: shows valid server as ok" {
  mkdir -p "$SAGE_HOME/mcp"
  echo '{"command":"bash","args":[]}' > "$SAGE_HOME/mcp/test-server.json"
  run "$SAGE" doctor --mcp
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-server"* ]]
  [[ "$output" == *"✓"* ]]
}

@test "doctor --mcp: flags missing command binary" {
  mkdir -p "$SAGE_HOME/mcp"
  echo '{"command":"nonexistent-binary-xyz","args":[]}' > "$SAGE_HOME/mcp/broken.json"
  run "$SAGE" doctor --mcp
  [ "$status" -ne 0 ]
  [[ "$output" == *"broken"* ]]
  [[ "$output" == *"✗"* ]] || [[ "$output" == *"not found"* ]]
}

@test "doctor --mcp: shows summary count" {
  mkdir -p "$SAGE_HOME/mcp"
  echo '{"command":"bash","args":[]}' > "$SAGE_HOME/mcp/s1.json"
  echo '{"command":"jq","args":[]}' > "$SAGE_HOME/mcp/s2.json"
  run "$SAGE" doctor --mcp
  [ "$status" -eq 0 ]
  [[ "$output" == *"2"* ]]
}

@test "doctor --all includes mcp check" {
  mkdir -p "$SAGE_HOME/mcp"
  echo '{"command":"bash","args":[]}' > "$SAGE_HOME/mcp/ok-server.json"
  run "$SAGE" doctor --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok-server"* ]]
  [[ "$output" == *"mcp"* ]] || [[ "$output" == *"MCP"* ]]
}
