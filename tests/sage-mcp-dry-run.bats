#!/usr/bin/env bats
# tests/sage-mcp-dry-run.bats — mcp rm --dry-run previews .json path without deleting
# Mirrors tests/sage-tool-dry-run.bats for the sibling mcp subsystem.

setup() {
  export SAGE_HOME=$(mktemp -d)
  mkdir -p "$SAGE_HOME/mcp"
  echo '{"command":"echo","args":[]}' > "$SAGE_HOME/mcp/myserver.json"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "mcp rm --dry-run previews without deleting" {
  run ./sage mcp rm myserver --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "would remove MCP server"
  echo "$output" | grep -q "myserver"
  [ -f "$SAGE_HOME/mcp/myserver.json" ]
}

@test "mcp rm --dry-run shows .json path" {
  run ./sage mcp rm myserver --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "myserver.json"
  [ -f "$SAGE_HOME/mcp/myserver.json" ]
}

@test "mcp rm --dry-run fails for nonexistent server" {
  run ./sage mcp rm nonexistent --dry-run
  [ "$status" -ne 0 ]
}
