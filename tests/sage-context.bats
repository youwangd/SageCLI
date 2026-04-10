#!/usr/bin/env bats
# tests/sage-context.bats — Shared context store tests

setup() {
  export SAGE_HOME=$(mktemp -d)
  mkdir -p "$SAGE_HOME"/{agents,runtimes,skills,context}
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init >/dev/null 2>&1 || true
}

teardown() {
  rm -rf "$SAGE_HOME"
}

# ── context set/get ──

@test "context set stores a value" {
  run sage context set mykey "hello world"
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/context/mykey" ]
  [ "$(cat "$SAGE_HOME/context/mykey")" = "hello world" ]
}

@test "context get retrieves a value" {
  echo -n "test-value" > "$SAGE_HOME/context/mykey"
  run sage context get mykey
  [ "$status" -eq 0 ]
  [[ "$output" == "test-value" ]]
}

@test "context get fails for missing key" {
  run sage context get nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "context set rejects invalid key" {
  run sage context set "bad key!" "value"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]]
}

@test "context set requires key and value" {
  run sage context set
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

# ── context ls ──

@test "context ls shows no context when empty" {
  run sage context ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"no context"* ]]
}

@test "context ls lists stored keys" {
  echo "v1" > "$SAGE_HOME/context/key1"
  echo "v2" > "$SAGE_HOME/context/key2"
  run sage context ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"key1"* ]]
  [[ "$output" == *"key2"* ]]
}

# ── context rm ──

@test "context rm removes a key" {
  echo "val" > "$SAGE_HOME/context/mykey"
  run sage context rm mykey
  [ "$status" -eq 0 ]
  [ ! -f "$SAGE_HOME/context/mykey" ]
}

@test "context rm fails for missing key" {
  run sage context rm nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

# ── context clear ──

@test "context clear removes all keys" {
  echo "v1" > "$SAGE_HOME/context/key1"
  echo "v2" > "$SAGE_HOME/context/key2"
  run sage context clear
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$SAGE_HOME/context/")" ]
}

# ── context requires subcommand ──

@test "context requires subcommand" {
  run sage context
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}
