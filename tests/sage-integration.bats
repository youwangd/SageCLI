#!/usr/bin/env bats
# Integration tests: full lifecycle (create → send → result → rm)

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-integ-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  # Create a bash runtime that echoes the message text
  cat > "$SAGE_HOME/runtimes/bash.sh" << 'RTEOF'
runtime_start() { :; }
runtime_inject() { echo "$2" | jq -r '.payload.text'; }
RTEOF
}

teardown() {
  rm -rf "$SAGE_HOME"
}

# ── full lifecycle: create → send → json result → rm ──

@test "integration: create → send --headless --json → verify result → rm" {
  "$SAGE" create worker --runtime bash >/dev/null 2>&1
  run "$SAGE" send worker "hello world" --headless --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "done"'
  echo "$output" | jq -e '.exit_code == 0'
  echo "$output" | jq -e '.output | contains("hello world")'
  # rm cleans up
  run "$SAGE" rm worker --force
  [ "$status" -eq 0 ]
  [ ! -d "$SAGE_HOME/agents/worker" ]
}

# ── skill injection persists through full send cycle ──

@test "integration: create --skill → send verifies skill prompt injected" {
  mkdir -p "$SAGE_HOME/skills/reviewer"
  cat > "$SAGE_HOME/skills/reviewer/skill.json" << 'EOF'
{"name":"reviewer","system_prompt":"You are a code reviewer."}
EOF
  "$SAGE" create coder --runtime bash --skill reviewer >/dev/null 2>&1
  run "$SAGE" send coder "review this" --headless
  [ "$status" -eq 0 ]
  [[ "$output" == *"You are a code reviewer."* ]]
  [[ "$output" == *"review this"* ]]
}

# ── context injection persists through full send cycle ──

@test "integration: context set → create → send verifies context injected" {
  "$SAGE" create bot --runtime bash >/dev/null 2>&1
  "$SAGE" context set project "acme"
  "$SAGE" context set env "prod"
  run "$SAGE" send bot "deploy" --headless
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Context]"* ]]
  [[ "$output" == *"project=acme"* ]]
  [[ "$output" == *"env=prod"* ]]
  [[ "$output" == *"deploy"* ]]
}

# ── skill + context compose together ──

@test "integration: skill + context both injected in single send" {
  mkdir -p "$SAGE_HOME/skills/ops"
  cat > "$SAGE_HOME/skills/ops/skill.json" << 'EOF'
{"name":"ops","system_prompt":"You are an ops engineer."}
EOF
  "$SAGE" create deployer --runtime bash --skill ops >/dev/null 2>&1
  "$SAGE" context set region "us-west-2"
  run "$SAGE" send deployer "scale up" --headless
  [ "$status" -eq 0 ]
  [[ "$output" == *"You are an ops engineer."* ]]
  [[ "$output" == *"[Context]"* ]]
  [[ "$output" == *"region=us-west-2"* ]]
  [[ "$output" == *"scale up"* ]]
}

# ── ls shows agent after create, gone after rm ──

@test "integration: create → ls shows agent → rm → ls shows empty" {
  "$SAGE" create alpha --runtime bash >/dev/null 2>&1
  run "$SAGE" ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  "$SAGE" rm alpha --force >/dev/null 2>&1
  run "$SAGE" ls
  [[ "$output" != *"alpha"* ]]
}

# ── context cleared between independent workflows ──

@test "integration: context clear removes all keys from injection" {
  "$SAGE" create worker --runtime bash >/dev/null 2>&1
  "$SAGE" context set key1 "val1"
  "$SAGE" context clear
  run "$SAGE" send worker "test" --headless
  [ "$status" -eq 0 ]
  [[ "$output" != *"[Context]"* ]]
  [[ "$output" == *"test"* ]]
}

# ── --no-context flag works in full lifecycle ──

@test "integration: context set → send --no-context skips injection" {
  "$SAGE" create worker --runtime bash >/dev/null 2>&1
  "$SAGE" context set secret "hidden"
  run "$SAGE" send worker "safe msg" --headless --no-context
  [ "$status" -eq 0 ]
  [[ "$output" != *"[Context]"* ]]
  [[ "$output" != *"hidden"* ]]
  [[ "$output" == *"safe msg"* ]]
}

# ── headless result tracking ──

@test "integration: send --headless writes result file retrievable by sage result" {
  "$SAGE" create worker --runtime bash >/dev/null 2>&1
  local json
  json=$("$SAGE" send worker "ping" --headless --json)
  local tid
  tid=$(echo "$json" | jq -r '.task_id')
  [ -n "$tid" ]
  run "$SAGE" result "$tid"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ping"* ]]
}
