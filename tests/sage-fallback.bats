#!/usr/bin/env bats
# tests/sage-fallback.bats — vendor kill-switch (Phase 20)

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-fallback-test-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  # Fake PATH where known runtime binaries are absent
  export FAKE_BIN="$BATS_TMPDIR/fallback-fake-bin-$$"
  mkdir -p "$FAKE_BIN"
  # bash is always available, so bash-runtime agents are "healthy" regardless.
  # We'll use llama-cpp (binary: llama-server) for "unreachable" primary because
  # it's extremely unlikely to be on a test host's PATH, and bash for healthy fallback.
  export PATH="$FAKE_BIN:/usr/bin:/bin"
}

teardown() {
  rm -rf "$SAGE_HOME" "$FAKE_BIN"
}

@test "fallback flag parsed without error" {
  "$SAGE" create primary --runtime bash >/dev/null
  "$SAGE" create backup --runtime bash >/dev/null
  # bash runtime is always healthy, no failover needed
  run "$SAGE" send primary "hi" --fallback backup --headless
  [ "$status" -eq 0 ]
}

@test "failover triggers when primary runtime binary is missing" {
  "$SAGE" create primary --runtime llama-cpp >/dev/null
  "$SAGE" create backup --runtime bash >/dev/null
  run "$SAGE" send primary "hi" --fallback backup --headless
  [ "$status" -eq 0 ]
  [[ "$output" == *"primary 'primary' runtime unreachable"* ]]
  [[ "$output" == *"failing over to 'backup'"* ]]
}

@test "chained fallbacks tried in order" {
  "$SAGE" create primary --runtime llama-cpp >/dev/null
  "$SAGE" create fb1 --runtime llama-cpp >/dev/null   # also unreachable
  "$SAGE" create fb2 --runtime bash >/dev/null        # healthy
  run "$SAGE" send primary "hi" --fallback fb1 --fallback fb2 --headless
  [ "$status" -eq 0 ]
  [[ "$output" == *"failing over to 'fb2'"* ]]
}

@test "error when all fallbacks unreachable" {
  "$SAGE" create primary --runtime llama-cpp >/dev/null
  "$SAGE" create fb1 --runtime llama-cpp >/dev/null
  run "$SAGE" send primary "hi" --fallback fb1 --headless
  [ "$status" -ne 0 ]
  [[ "$output" == *"and all fallbacks"* ]]
  [[ "$output" == *"are unreachable"* ]]
}

@test "fallback skipped when primary is healthy" {
  "$SAGE" create primary --runtime bash >/dev/null
  "$SAGE" create backup --runtime bash >/dev/null
  run "$SAGE" send primary "hi" --fallback backup --headless
  [ "$status" -eq 0 ]
  # Should NOT have failover message
  [[ "$output" != *"failing over"* ]]
}
