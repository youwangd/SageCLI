#!/usr/bin/env bats
# tests/sage-history-grep.bats — tests for sage history --grep <pattern>

setup() {
  export SAGE_HOME=$(mktemp -d)
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init --quiet 2>/dev/null || true
  # Create two agents with task history
  sage create alpha --runtime bash --quiet 2>/dev/null || true
  sage create beta --runtime bash --quiet 2>/dev/null || true
  local agents_dir="$SAGE_HOME/agents"
  mkdir -p "$agents_dir/alpha/results" "$agents_dir/beta/results"
  local now=$(date +%s)
  # alpha: task about "auth migration"
  cat > "$agents_dir/alpha/results/t001.status.json" <<EOF
{"id":"t001","status":"done","queued_at":$now,"started_at":$now,"finished_at":$((now+10)),"task_text":"Review the auth migration PR"}
EOF
  # alpha: task about "deploy"
  cat > "$agents_dir/alpha/results/t002.status.json" <<EOF
{"id":"t002","status":"done","queued_at":$((now+1)),"started_at":$((now+1)),"finished_at":$((now+20)),"task_text":"Deploy to staging"}
EOF
  # beta: task about "auth tests"
  cat > "$agents_dir/beta/results/t003.status.json" <<EOF
{"id":"t003","status":"done","queued_at":$((now+2)),"started_at":$((now+2)),"finished_at":$((now+15)),"task_text":"Write auth unit tests"}
EOF
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "history --grep filters tasks by pattern" {
  run sage history --grep "auth"
  [ "$status" -eq 0 ]
  [[ "$output" == *"t001"* ]]
  [[ "$output" == *"t003"* ]]
  [[ "$output" != *"t002"* ]]
}

@test "history --grep is case-insensitive" {
  run sage history --grep "AUTH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"t001"* ]]
  [[ "$output" == *"t003"* ]]
}

@test "history --grep with no matches shows info" {
  run sage history --grep "nonexistent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no task history"* ]] || [[ -z "$(echo "$output" | grep 't00')" ]]
}

@test "history --grep combines with --agent filter" {
  run sage history --grep "auth" --agent alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"t001"* ]]
  [[ "$output" != *"t003"* ]]
}
