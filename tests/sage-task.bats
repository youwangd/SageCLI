#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-task-test-$$"
  "$SAGE" init 2>/dev/null
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "sage task with no args shows usage" {
  run "$SAGE" task
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "sage task --list works with no templates" {
  run "$SAGE" task --list
  [ "$status" -eq 0 ]
}

@test "sage task --list shows available templates" {
  mkdir -p "$SAGE_HOME/tasks"
  cat > "$SAGE_HOME/tasks/review.md" <<'EOF'
---
description: Code review
runtime: bash
input: files
---
Review the following code.
EOF
  run "$SAGE" task --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"review"* ]]
  [[ "$output" == *"Code review"* ]]
}

@test "sage task with nonexistent template fails" {
  run "$SAGE" task nonexistent-template
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "sage task with files-input template but no files fails" {
  mkdir -p "$SAGE_HOME/tasks"
  cat > "$SAGE_HOME/tasks/review.md" <<'EOF'
---
description: Code review
runtime: bash
input: files
---
Review the code.
EOF
  run "$SAGE" task review
  [ "$status" -ne 0 ]
  [[ "$output" == *"expects files"* ]]
}
