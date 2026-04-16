#!/usr/bin/env bats
# tests/sage-send-timeout.bats — per-task timeout for headless send

setup() {
  export SAGE_HOME="$(mktemp -d)"
  mkdir -p "$SAGE_HOME/agents" "$SAGE_HOME/runtimes" "$SAGE_HOME/tools" "$SAGE_HOME/logs"
  # Minimal runtime that sleeps (simulates slow task)
  cat > "$SAGE_HOME/runtimes/bash.sh" << 'EOF'
runtime_start() { :; }
runtime_inject() { sleep 10; echo "done"; }
runtime_stop() { :; }
EOF
  # Fast runtime for non-timeout tests
  cat > "$SAGE_HOME/runtimes/fast.sh" << 'EOF'
runtime_start() { :; }
runtime_inject() { echo "fast result"; }
runtime_stop() { :; }
EOF
  cat > "$SAGE_HOME/tools/common.sh" << 'EOF'
send_msg() { echo "task-$(date +%s)"; }
EOF
  # Create test agent
  mkdir -p "$SAGE_HOME/agents/tester"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/tester/runtime.json"
  mkdir -p "$SAGE_HOME/agents/fast-agent"
  echo '{"runtime":"fast"}' > "$SAGE_HOME/agents/fast-agent/runtime.json"
  # Copy runtimes dir
  cp -r "$SAGE_HOME/runtimes" "$SAGE_HOME/runtimes_bak" 2>/dev/null || true
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "send --timeout requires --headless" {
  run ./sage send tester "hello" --timeout 5
  [ "$status" -ne 0 ]
  [[ "$output" == *"--timeout requires --headless"* ]]
}

@test "send --headless --timeout kills slow task with exit 124" {
  run timeout 8 ./sage send tester "slow task" --headless --timeout 2
  [ "$status" -eq 124 ]
}

@test "send --headless --timeout accepts duration format (Ns)" {
  run timeout 8 ./sage send tester "slow task" --headless --timeout 2s
  [ "$status" -eq 124 ]
}

@test "send --headless --timeout fast task completes normally" {
  run ./sage send fast-agent "quick task" --headless --timeout 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"fast result"* ]]
}
