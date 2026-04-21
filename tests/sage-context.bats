#!/usr/bin/env bats
# tests/sage-context.bats — Shared context store tests

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-context-test-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

# ── context set/get ──

@test "context set stores a value" {
  run "$SAGE" context set mykey "hello world"
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/context/mykey" ]
  [ "$(cat "$SAGE_HOME/context/mykey")" = "hello world" ]
}

@test "context get retrieves a value" {
  echo -n "test-value" > "$SAGE_HOME/context/mykey"
  run "$SAGE" context get mykey
  [ "$status" -eq 0 ]
  [[ "$output" == "test-value" ]]
}

@test "context get fails for missing key" {
  run "$SAGE" context get nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "context set rejects invalid key" {
  run "$SAGE" context set "bad key!" "value"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]]
}

@test "context set requires key and value" {
  run "$SAGE" context set
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

# ── context ls ──

@test "context ls shows no context when empty" {
  run "$SAGE" context ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"no context"* ]]
}

@test "context ls lists stored keys" {
  echo "v1" > "$SAGE_HOME/context/key1"
  echo "v2" > "$SAGE_HOME/context/key2"
  run "$SAGE" context ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"key1"* ]]
  [[ "$output" == *"key2"* ]]
}

# ── context rm ──

@test "context rm removes a key" {
  echo "val" > "$SAGE_HOME/context/mykey"
  run "$SAGE" context rm mykey
  [ "$status" -eq 0 ]
  [ ! -f "$SAGE_HOME/context/mykey" ]
}

@test "context rm fails for missing key" {
  run "$SAGE" context rm nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

# ── context clear ──

@test "context clear removes all keys" {
  echo "v1" > "$SAGE_HOME/context/key1"
  echo "v2" > "$SAGE_HOME/context/key2"
  run "$SAGE" context clear
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$SAGE_HOME/context/")" ]
}

# ── context requires subcommand ──

@test "context requires subcommand" {
  run "$SAGE" context
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

# ── context auto-inject on send ──

@test "send --headless injects context into message" {
  # Create agent with bash runtime
  "$SAGE" create worker
  cat > "$SAGE_HOME/runtimes/bash.sh" << 'RTEOF'
runtime_start() { :; }
runtime_inject() {
  local msg="$2"
  echo "$msg" | jq -r '.payload.text'
}
RTEOF

  # Set context keys
  "$SAGE" context set project "acme"
  "$SAGE" context set env "staging"

  run "$SAGE" send worker "deploy now" --headless
  [ "$status" -eq 0 ]
  [[ "$output" == *"[Context]"* ]]
  [[ "$output" == *"project=acme"* ]]
  [[ "$output" == *"env=staging"* ]]
  [[ "$output" == *"deploy now"* ]]
}

@test "send --headless skips context injection when no keys" {
  "$SAGE" create worker
  cat > "$SAGE_HOME/runtimes/bash.sh" << 'RTEOF'
runtime_start() { :; }
runtime_inject() {
  local msg="$2"
  echo "$msg" | jq -r '.payload.text'
}
RTEOF

  run "$SAGE" send worker "deploy now" --headless
  [ "$status" -eq 0 ]
  [[ "$output" != *"[Context]"* ]]
  [[ "$output" == *"deploy now"* ]]
}

@test "send --headless --no-context skips injection even with keys" {
  "$SAGE" create worker
  cat > "$SAGE_HOME/runtimes/bash.sh" << 'RTEOF'
runtime_start() { :; }
runtime_inject() {
  local msg="$2"
  echo "$msg" | jq -r '.payload.text'
}
RTEOF

  "$SAGE" context set project "acme"

  run "$SAGE" send worker "deploy now" --headless --no-context
  [ "$status" -eq 0 ]
  [[ "$output" != *"[Context]"* ]]
  [[ "$output" == *"deploy now"* ]]
}

# ── context clear --dry-run ──

@test "context clear --dry-run does not delete keys" {
  "$SAGE" context set k1 "v1"
  "$SAGE" context set k2 "v2"
  run "$SAGE" context clear --dry-run
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/context/k1" ]
  [ -f "$SAGE_HOME/context/k2" ]
}

@test "context clear --dry-run reports count and keys" {
  "$SAGE" context set alpha "1"
  "$SAGE" context set beta "2"
  run "$SAGE" context clear --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"2"* ]]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"beta"* ]]
}

@test "context clear --dry-run with no keys reports would clear 0" {
  run "$SAGE" context clear --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would"* ]]
  [[ "$output" == *"0"* ]]
}
