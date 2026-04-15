#!/usr/bin/env bats

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage_status_task_$$"
  mkdir -p "$SAGE_HOME/agents"
  ./sage init --force >/dev/null 2>&1 || true
  mkdir -p "$SAGE_HOME/agents/worker/results" "$SAGE_HOME/agents/worker/inbox"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/worker/runtime.json"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "status shows TASK column header" {
  local output=$(./sage status 2>/dev/null)
  echo "$output" | grep -q "TASK"
}

@test "status shows task text for agent with active task" {
  local tid="task-$(date +%s)"
  printf '{"id":"%s","from":"test","status":"queued","queued_at":%d,"started_at":null,"finished_at":null,"task_text":"analyze the codebase"}' \
    "$tid" "$(date +%s)" > "$SAGE_HOME/agents/worker/results/${tid}.status.json"
  local output=$(./sage status 2>/dev/null)
  echo "$output" | grep -q "analyze the code"
}

@test "status shows dash for agent with no active task" {
  local output=$(./sage status 2>/dev/null)
  # The TASK column for worker should be a dash
  echo "$output" | grep "worker" | grep -qE "—|—"
}

@test "status truncates long task text" {
  local tid="task-$(date +%s)"
  local long_text="this is a very long task description that should be truncated because it exceeds the column width limit set"
  printf '{"id":"%s","from":"test","status":"queued","queued_at":%d,"started_at":null,"finished_at":null,"task_text":"%s"}' \
    "$tid" "$(date +%s)" "$long_text" > "$SAGE_HOME/agents/worker/results/${tid}.status.json"
  local output=$(./sage status 2>/dev/null)
  echo "$output" | grep -q "\.\.\."
}
