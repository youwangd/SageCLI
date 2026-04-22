#!/usr/bin/env bats
# tests/sage-mcp-count.bats — mcp ls --count prints plain integer

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

@test "mcp ls --count prints 0 when no MCP servers registered" {
  run sage mcp ls --count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "mcp ls --count prints integer count of registered MCP servers" {
  echo '{"command":"foo","args":[]}' > "$SAGE_HOME/mcp/alpha.json"
  echo '{"command":"bar","args":[]}' > "$SAGE_HOME/mcp/beta.json"
  echo '{"command":"baz","args":[]}' > "$SAGE_HOME/mcp/gamma.json"
  run sage mcp ls --count
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "mcp ls --count output is scriptable (pure digits)" {
  echo '{"command":"foo","args":[]}' > "$SAGE_HOME/mcp/one.json"
  run sage mcp ls --count
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
}
