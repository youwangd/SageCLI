#!/usr/bin/env bats
# tests/sage-ls-tree.bats — ls --tree shows agent parent/child hierarchy

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-ls-tree-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "ls --tree shows root agents at top level" {
  "$SAGE" create alpha --runtime bash >/dev/null 2>&1
  "$SAGE" create beta --runtime bash >/dev/null 2>&1
  run "$SAGE" ls --tree
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"beta"* ]]
}

@test "ls --tree shows children indented under parent" {
  "$SAGE" create parent1 --runtime bash >/dev/null 2>&1
  # Manually create child with parent field
  local child_dir="$SAGE_HOME/agents/child1"
  mkdir -p "$child_dir"
  echo '{"runtime":"bash","parent":"parent1"}' > "$child_dir/runtime.json"
  run "$SAGE" ls --tree
  [ "$status" -eq 0 ]
  [[ "$output" == *"parent1"* ]]
  # child should appear with tree drawing chars
  echo "$output" | grep -qE '[└├].*child1'
}

@test "ls --tree errors when combined with --json" {
  run "$SAGE" ls --tree --json
  [ "$status" -ne 0 ]
  [[ "$output" == *"--tree"* ]]
}

@test "ls --tree works with --stopped filter" {
  "$SAGE" create worker --runtime bash >/dev/null 2>&1
  run "$SAGE" ls --tree --stopped
  [ "$status" -eq 0 ]
  [[ "$output" == *"worker"* ]]
}
