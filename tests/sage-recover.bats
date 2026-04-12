#!/usr/bin/env bats

setup() {
  export SAGE_HOME=$(mktemp -d)
  export AGENTS_DIR="$SAGE_HOME/agents"
  export CHECKPOINTS_DIR="$SAGE_HOME/checkpoints"
  mkdir -p "$AGENTS_DIR" "$CHECKPOINTS_DIR"
  SAGE="$BATS_TEST_DIRNAME/../sage"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "recover reports nothing when no agents or tmux windows" {
  # No tmux session = nothing to recover
  run bash "$SAGE" recover
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"nothing to recover"* ]]
}

@test "recover detects dead agent with stale pid" {
  mkdir -p "$AGENTS_DIR/dead-agent"
  echo '{"name":"dead-agent","model":"test"}' > "$AGENTS_DIR/dead-agent/runtime.json"
  echo "99999" > "$AGENTS_DIR/dead-agent/.pid"
  run bash "$SAGE" recover --yes
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"dead-agent"* ]]
  [[ "$output" == *"stale"* || "$output" == *"cleaned"* || "$output" == *"dead"* ]]
}

@test "recover cleans stale pid for dead agent without checkpoint" {
  mkdir -p "$AGENTS_DIR/no-ckpt"
  echo '{"name":"no-ckpt","model":"test"}' > "$AGENTS_DIR/no-ckpt/runtime.json"
  echo "99999" > "$AGENTS_DIR/no-ckpt/.pid"
  run bash "$SAGE" recover --yes
  [[ "$status" -eq 0 ]]
  # Stale pid should be removed
  [[ ! -f "$AGENTS_DIR/no-ckpt/.pid" ]]
}

@test "recover restores dead agent from checkpoint" {
  # Create a checkpoint but no agent dir
  cat > "$CHECKPOINTS_DIR/ckpt-agent.json" <<'EOF'
{"name":"ckpt-agent","runtime":{"name":"ckpt-agent","model":"test"},"env":{},"mcp":null,"steer":null,"was_running":true,"timestamp":"2026-04-12T00:00:00Z"}
EOF
  run bash "$SAGE" recover --yes
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"ckpt-agent"* ]]
  [[ "$output" == *"restor"* ]]
}

@test "recover with --yes skips confirmation prompts" {
  mkdir -p "$AGENTS_DIR/auto-clean"
  echo '{"name":"auto-clean","model":"test"}' > "$AGENTS_DIR/auto-clean/runtime.json"
  echo "99999" > "$AGENTS_DIR/auto-clean/.pid"
  run bash "$SAGE" recover --yes
  [[ "$status" -eq 0 ]]
  [[ ! -f "$AGENTS_DIR/auto-clean/.pid" ]]
}

@test "recover shows summary count" {
  mkdir -p "$AGENTS_DIR/d1" "$AGENTS_DIR/d2"
  echo '{"name":"d1","model":"t"}' > "$AGENTS_DIR/d1/runtime.json"
  echo '{"name":"d2","model":"t"}' > "$AGENTS_DIR/d2/runtime.json"
  echo "99998" > "$AGENTS_DIR/d1/.pid"
  echo "99997" > "$AGENTS_DIR/d2/.pid"
  run bash "$SAGE" recover --yes
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"2"* ]]
}

@test "recover does not touch running agents" {
  mkdir -p "$AGENTS_DIR/alive"
  echo '{"name":"alive","model":"t"}' > "$AGENTS_DIR/alive/runtime.json"
  echo "$$" > "$AGENTS_DIR/alive/.pid"  # current process PID = alive
  run bash "$SAGE" recover --yes
  [[ "$status" -eq 0 ]]
  # PID file should still exist
  [[ -f "$AGENTS_DIR/alive/.pid" ]]
}
