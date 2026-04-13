#!/usr/bin/env bats

setup() {
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  export SAGE_HOME="$BATS_TEST_TMPDIR/sage-strict-$$"
  sage init --quiet 2>/dev/null || true
}

teardown() {
  rm -rf "$SAGE_HOME" 2>/dev/null || true
}

@test "send --strict requires --headless" {
  sage create worker test-strict --runtime bash 2>/dev/null
  run sage send test-strict "hello" --strict
  [ "$status" -ne 0 ]
  [[ "$output" == *"--strict requires --headless"* ]]
}

@test "send --strict detects TODO in output and retries" {
  sage create worker strict-todo --runtime bash 2>/dev/null
  local agent_dir="$SAGE_HOME/agents/strict-todo"
  # Create a bash script that outputs TODO on first call, then completes
  local call_count="$BATS_TEST_TMPDIR/strict-call-count-$$"
  echo "0" > "$call_count"
  cat > "$agent_dir/run.sh" << 'SCRIPT'
#!/usr/bin/env bash
COUNT_FILE="__CALL_COUNT__"
c=$(cat "$COUNT_FILE"); c=$((c+1)); echo "$c" > "$COUNT_FILE"
if [ "$c" -eq 1 ]; then echo "TODO: finish the rest later"; else echo "Task completed successfully"; fi
SCRIPT
  sed -i "s|__CALL_COUNT__|$call_count|g" "$agent_dir/run.sh"
  chmod +x "$agent_dir/run.sh"
  run sage send strict-todo "do the task" --headless --strict
  [ "$status" -eq 0 ]
  [[ "$output" == *"completed"* ]]
}

@test "send --strict exits 2 after max retries on persistent incomplete output" {
  sage create worker strict-lazy --runtime bash 2>/dev/null
  local agent_dir="$SAGE_HOME/agents/strict-lazy"
  cat > "$agent_dir/run.sh" << 'SCRIPT'
#!/usr/bin/env bash
echo "I will do this later when I have more time"
SCRIPT
  chmod +x "$agent_dir/run.sh"
  run sage send strict-lazy "do the task" --headless --strict
  [ "$status" -eq 2 ]
}

@test "send --strict passes clean output without retry" {
  sage create worker strict-clean --runtime bash 2>/dev/null
  local agent_dir="$SAGE_HOME/agents/strict-clean"
  cat > "$agent_dir/run.sh" << 'SCRIPT'
#!/usr/bin/env bash
echo "All tasks completed. Here is the result."
SCRIPT
  chmod +x "$agent_dir/run.sh"
  run sage send strict-clean "do the task" --headless --strict
  [ "$status" -eq 0 ]
  [[ "$output" == *"All tasks completed"* ]]
}

@test "send --strict detects multiple incompleteness markers" {
  sage create worker strict-multi --runtime bash 2>/dev/null
  local agent_dir="$SAGE_HOME/agents/strict-multi"
  cat > "$agent_dir/run.sh" << 'SCRIPT'
#!/usr/bin/env bash
echo "FIXME: this needs work. I cannot complete this right now."
SCRIPT
  chmod +x "$agent_dir/run.sh"
  run sage send strict-multi "do the task" --headless --strict
  [ "$status" -eq 2 ]
}
