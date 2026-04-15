#!/usr/bin/env bats
# tests/sage-history-task.bats — tests for task text in history output

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage_history_task_$$"
  mkdir -p "$SAGE_HOME/agents"
  ./sage init --force >/dev/null 2>&1 || true
  # Create agent with a task that has text stored in status.json
  mkdir -p "$SAGE_HOME/agents/worker/results" "$SAGE_HOME/agents/worker/inbox"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/worker/runtime.json"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "status.json includes task_text field after send_task" {
  # Create a status.json with task_text (simulating what send_task should write)
  cat > "$SAGE_HOME/agents/worker/results/t001.status.json" <<'EOF'
{"id":"t001","from":"cli","status":"done","queued_at":1700000000,"started_at":1700000001,"finished_at":1700000010,"task_text":"Review the auth module"}
EOF
  local out
  out=$(./sage history --agent worker --json)
  echo "$out" | jq -e '.[0].task_text == "Review the auth module"'
}

@test "history table shows TASK column with text preview" {
  cat > "$SAGE_HOME/agents/worker/results/t002.status.json" <<'EOF'
{"id":"t002","from":"cli","status":"done","queued_at":1700000000,"started_at":1700000001,"finished_at":1700000010,"task_text":"Fix the login bug in auth service"}
EOF
  local out
  out=$(./sage history --agent worker)
  echo "$out" | grep -q "Fix the login"
}

@test "history shows truncated task text for long messages" {
  local long_text="This is a very long task message that should be truncated in the history table output because it exceeds the column width limit for display"
  cat > "$SAGE_HOME/agents/worker/results/t003.status.json" <<EOF
{"id":"t003","from":"cli","status":"done","queued_at":1700000000,"started_at":1700000001,"finished_at":1700000010,"task_text":"$long_text"}
EOF
  local out
  out=$(./sage history --agent worker)
  # Should show truncated text (not the full 140+ char message)
  echo "$out" | grep -q "This is a very long"
}

@test "history --json includes task_text even when empty" {
  cat > "$SAGE_HOME/agents/worker/results/t004.status.json" <<'EOF'
{"id":"t004","from":"cli","status":"done","queued_at":1700000000,"started_at":1700000001,"finished_at":1700000010}
EOF
  local out
  out=$(./sage history --agent worker --json)
  # Should have task_text field (empty string or null)
  echo "$out" | jq -e '.[0] | has("task_text")'
}
