#!/usr/bin/env bats
# tests/sage-mcp.bats — MCP server integration tests

setup() {
  export SAGE_HOME=$(mktemp -d)
  mkdir -p "$SAGE_HOME"/{agents,runtimes,mcp}
  cat > "$SAGE_HOME/runtimes/bash.sh" << 'EOF'
runtime_start() { :; }
runtime_inject() { echo "ok"; }
EOF
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init >/dev/null 2>&1 || true
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "mcp add registers a server in registry" {
  run sage mcp add myserver --command "npx" --args "-y,@modelcontextprotocol/server-filesystem,/tmp"
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/mcp/myserver.json" ]
  run jq -r '.command' "$SAGE_HOME/mcp/myserver.json"
  [ "$output" = "npx" ]
}

@test "mcp ls lists registered servers" {
  sage mcp add srv1 --command "node" --args "srv1.js"
  sage mcp add srv2 --command "python" --args "srv2.py"
  run sage mcp ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"srv1"* ]]
  [[ "$output" == *"srv2"* ]]
}

@test "mcp rm removes a server from registry" {
  sage mcp add myserver --command "node" --args "server.js"
  run sage mcp rm myserver
  [ "$status" -eq 0 ]
  [ ! -f "$SAGE_HOME/mcp/myserver.json" ]
}

@test "create --mcp stores mcp_servers in runtime.json" {
  sage mcp add github --command "npx" --args "-y,@modelcontextprotocol/server-github"
  run sage create worker --mcp github
  [ "$status" -eq 0 ]
  run jq -r '.mcp_servers[0]' "$SAGE_HOME/agents/worker/runtime.json"
  [ "$output" = "github" ]
}

@test "create --mcp writes mcp.json to agent dir" {
  sage mcp add fs --command "npx" --args "-y,@modelcontextprotocol/server-filesystem,/tmp"
  run sage create worker --mcp fs
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/agents/worker/mcp.json" ]
  run jq -r '.mcpServers.fs.command' "$SAGE_HOME/agents/worker/mcp.json"
  [ "$output" = "npx" ]
}

@test "create --mcp with multiple servers" {
  sage mcp add srv1 --command "node" --args "a.js"
  sage mcp add srv2 --command "python" --args "b.py"
  run sage create worker --mcp srv1,srv2
  [ "$status" -eq 0 ]
  run jq '.mcpServers | keys | length' "$SAGE_HOME/agents/worker/mcp.json"
  [ "$output" = "2" ]
}

@test "create --mcp rejects unknown server" {
  run sage create worker --mcp nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown MCP server"* ]]
}

@test "mcp add rejects missing --command" {
  run sage mcp add myserver
  [ "$status" -ne 0 ]
}
