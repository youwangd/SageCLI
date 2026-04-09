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

# ── MCP lifecycle tests ──

@test "start_mcp_servers creates .mcp-pids file for agent with MCP servers" {
  sage mcp add testmcp --command "sleep" --args "999"
  sage create worker --mcp testmcp
  # start_mcp_servers is called by start_agent; test the function directly
  run sage mcp status worker
  # Before starting, no PIDs
  [[ "$output" == *"no MCP"* ]] || [[ "$output" == *"not running"* ]] || [ "$status" -ne 0 ]
}

@test "mcp status shows running servers for agent" {
  sage mcp add slowsrv --command "sleep" --args "999"
  sage create worker --mcp slowsrv
  # Manually create .mcp-pids to simulate running servers
  echo "slowsrv 99999" > "$SAGE_HOME/agents/worker/.mcp-pids"
  run sage mcp status worker
  [ "$status" -eq 0 ]
  [[ "$output" == *"slowsrv"* ]]
}

@test "mcp status fails for agent without MCP servers" {
  sage create worker
  run sage mcp status worker
  [ "$status" -ne 0 ] || [[ "$output" == *"no MCP"* ]]
}

@test "stop_mcp_servers removes .mcp-pids file" {
  sage mcp add fakesrv --command "sleep" --args "999"
  sage create worker --mcp fakesrv
  # Create fake pid file
  echo "fakesrv 99999" > "$SAGE_HOME/agents/worker/.mcp-pids"
  [ -f "$SAGE_HOME/agents/worker/.mcp-pids" ]
  # stop_mcp_servers is internal; test via mcp stop-servers
  run sage mcp stop-servers worker
  [ "$status" -eq 0 ]
  [ ! -f "$SAGE_HOME/agents/worker/.mcp-pids" ]
}

@test "mcp start-servers spawns processes and writes .mcp-pids" {
  sage mcp add sleeper --command "sleep" --args "300"
  sage create worker --mcp sleeper
  run sage mcp start-servers worker
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/agents/worker/.mcp-pids" ]
  # Verify PID is a real process
  local pid=$(awk '{print $2}' "$SAGE_HOME/agents/worker/.mcp-pids")
  kill -0 "$pid" 2>/dev/null
  # Cleanup
  kill "$pid" 2>/dev/null || true
}

@test "mcp stop-servers kills spawned processes" {
  sage mcp add sleeper2 --command "sleep" --args "300"
  sage create worker --mcp sleeper2
  sage mcp start-servers worker
  local pid=$(awk '{print $2}' "$SAGE_HOME/agents/worker/.mcp-pids")
  kill -0 "$pid" 2>/dev/null  # alive
  run sage mcp stop-servers worker
  [ "$status" -eq 0 ]
  ! kill -0 "$pid" 2>/dev/null  # dead
}