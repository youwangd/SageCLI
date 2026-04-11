#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-msg-test-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  # Create agent dirs directly (no runtime needed for msg tests)
  mkdir -p "$SAGE_HOME/agents/sender" "$SAGE_HOME/agents/receiver"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

# --- msg send ---

@test "msg send delivers message to receiver" {
  run "$SAGE" msg send sender receiver "found a bug in auth module"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sent"* ]]
  local count=$(find "$SAGE_HOME/agents/receiver/messages" -name "*.json" 2>/dev/null | wc -l)
  [ "$count" -eq 1 ]
}

@test "msg send stores correct JSON fields" {
  "$SAGE" msg send sender receiver "test message"
  local msg_file=$(ls -t "$SAGE_HOME/agents/receiver/messages"/*.json 2>/dev/null | head -1)
  [ -f "$msg_file" ]
  local from=$(jq -r '.from' "$msg_file")
  local text=$(jq -r '.text' "$msg_file")
  [ "$from" = "sender" ]
  [ "$text" = "test message" ]
  local ts=$(jq -r '.ts' "$msg_file")
  [[ "$ts" =~ ^[0-9]+$ ]]
}

@test "msg send fails with missing args" {
  run "$SAGE" msg send sender
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "msg send fails for nonexistent receiver" {
  run "$SAGE" msg send sender ghost "hello"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "msg send multiple messages accumulate" {
  "$SAGE" msg send sender receiver "msg1"
  sleep 1
  "$SAGE" msg send sender receiver "msg2"
  sleep 1
  "$SAGE" msg send sender receiver "msg3"
  local count=$(find "$SAGE_HOME/agents/receiver/messages" -name "*.json" 2>/dev/null | wc -l)
  [ "$count" -eq 3 ]
}

# --- msg ls ---

@test "msg ls shows messages for agent" {
  "$SAGE" msg send sender receiver "hello from sender"
  run "$SAGE" msg ls receiver
  [ "$status" -eq 0 ]
  [[ "$output" == *"sender"* ]]
  [[ "$output" == *"hello from sender"* ]]
}

@test "msg ls --json outputs valid JSON" {
  "$SAGE" msg send sender receiver "json test"
  run "$SAGE" msg ls receiver --json
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null 2>&1
}

@test "msg ls shows empty state" {
  run "$SAGE" msg ls receiver
  [ "$status" -eq 0 ]
  [[ "$output" == *"no messages"* ]]
}

# --- msg clear ---

@test "msg clear removes all messages" {
  "$SAGE" msg send sender receiver "msg1"
  "$SAGE" msg send sender receiver "msg2"
  run "$SAGE" msg clear receiver
  [ "$status" -eq 0 ]
  [[ "$output" == *"cleared"* ]]
  local count=$(find "$SAGE_HOME/agents/receiver/messages" -name "*.json" 2>/dev/null | wc -l)
  [ "$count" -eq 0 ]
}

@test "msg clear on empty is safe" {
  run "$SAGE" msg clear receiver
  [ "$status" -eq 0 ]
}

# --- msg usage ---

@test "msg without subcommand shows usage" {
  run "$SAGE" msg
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

# ═══ Auto-injection tests ═══

@test "msg: send auto-injects unread messages into prompt on headless send" {
  # Set up receiver as bash agent with proper handler
  mkdir -p "$SAGE_HOME/agents/injrcv"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/injrcv/runtime.json"
  cat > "$SAGE_HOME/agents/injrcv/handler.sh" <<'SH'
#!/bin/bash
handle_message() { local msg="$1"; echo "got: $(echo "$msg" | jq -r '.payload.text')"; }
SH
  chmod +x "$SAGE_HOME/agents/injrcv/handler.sh"
  "$SAGE" msg send sender injrcv "check the auth module"
  run "$SAGE" send injrcv "do work" --headless
  [[ "$output" == *"[Messages]"* ]]
  [[ "$output" == *"check the auth module"* ]]
}

@test "msg: messages are cleared after injection" {
  mkdir -p "$SAGE_HOME/agents/clrrcv"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/clrrcv/runtime.json"
  cat > "$SAGE_HOME/agents/clrrcv/handler.sh" <<'SH'
#!/bin/bash
handle_message() { echo "ok"; }
SH
  chmod +x "$SAGE_HOME/agents/clrrcv/handler.sh"
  "$SAGE" msg send sender clrrcv "first message"
  "$SAGE" send clrrcv "do work" --headless
  # messages should be cleared after injection
  run "$SAGE" msg ls clrrcv --json
  [ "$output" = "[]" ]
}

@test "msg: no injection when no messages exist" {
  mkdir -p "$SAGE_HOME/agents/norcv"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/norcv/runtime.json"
  cat > "$SAGE_HOME/agents/norcv/handler.sh" <<'SH'
#!/bin/bash
handle_message() { echo "hi"; }
SH
  chmod +x "$SAGE_HOME/agents/norcv/handler.sh"
  run "$SAGE" send norcv "do work" --headless
  [[ "$output" != *"[Messages]"* ]]
}

# --- send --retry ---

@test "send --retry requires --headless" {
  run "$SAGE" send worker "echo hi" --retry 3
  [ "$status" -eq 1 ]
  [[ "$output" == *"--headless"* ]]
}

@test "send --retry retries on failure then succeeds" {
  # Create agent that fails twice then succeeds (uses a counter file)
  local counter_file="$SAGE_HOME/retry_counter"
  echo "0" > "$counter_file"
  mkdir -p "$SAGE_HOME/agents/flaky"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/flaky/runtime.json"
  cat > "$SAGE_HOME/agents/flaky/handler.sh" <<SH
#!/bin/bash
handle_message() {
  local c=\$(cat "$counter_file")
  c=\$((c + 1))
  echo "\$c" > "$counter_file"
  if [ "\$c" -lt 3 ]; then
    echo "attempt \$c failed"
    return 1
  fi
  echo "attempt \$c succeeded"
}
SH
  chmod +x "$SAGE_HOME/agents/flaky/handler.sh"
  run "$SAGE" send flaky "do it" --headless --retry 3
  [ "$status" -eq 0 ]
  [[ "$output" == *"succeeded"* ]]
}

@test "send --retry exhausts retries and fails" {
  local counter_file="$SAGE_HOME/fail_counter"
  echo "0" > "$counter_file"
  mkdir -p "$SAGE_HOME/agents/alwaysfail"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/alwaysfail/runtime.json"
  cat > "$SAGE_HOME/agents/alwaysfail/handler.sh" <<SH
#!/bin/bash
handle_message() {
  local c=\$(cat "$counter_file")
  c=\$((c + 1))
  echo "\$c" > "$counter_file"
  echo "fail \$c"; return 1
}
SH
  chmod +x "$SAGE_HOME/agents/alwaysfail/handler.sh"
  run "$SAGE" send alwaysfail "do it" --headless --retry 2
  [ "$status" -ne 0 ]
  # Should have attempted 3 times (1 initial + 2 retries)
  local attempts
  attempts=$(cat "$counter_file")
  [ "$attempts" -eq 3 ]
}
