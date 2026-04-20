#!/usr/bin/env bats
# tests/sage-mcp-json.bats — mcp ls --json machine-readable output

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

@test "mcp ls --json emits empty array when no servers registered" {
  run sage mcp ls --json
  [ "$status" -eq 0 ]
  run bash -c 'sage mcp ls --json | jq "length"'
  [ "$output" = "0" ]
}

@test "mcp ls --json emits array of server objects with name/command/args" {
  sage mcp add srv1 --command "node" --args "a.js,b.js"
  sage mcp add srv2 --command "python" --args "s.py"
  run bash -c 'sage mcp ls --json | jq -r ".[].name" | sort'
  [ "$status" -eq 0 ]
  [[ "$output" == *"srv1"* ]]
  [[ "$output" == *"srv2"* ]]
}

@test "mcp ls --json preserves command and args fields per server" {
  sage mcp add myserver --command "npx" --args "-y,@scope/pkg,/tmp"
  run bash -c 'sage mcp ls --json | jq -r ".[] | select(.name==\"myserver\") | .command"'
  [ "$output" = "npx" ]
  run bash -c 'sage mcp ls --json | jq -r ".[] | select(.name==\"myserver\") | .args | length"'
  [ "$output" = "3" ]
}
