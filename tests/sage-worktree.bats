#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-wt-test-$$"
  rm -rf "$SAGE_HOME"
  # Create a git repo to test worktree operations
  export TEST_REPO="$BATS_TMPDIR/sage-wt-repo-$$"
  rm -rf "$TEST_REPO"
  mkdir -p "$TEST_REPO"
  cd "$TEST_REPO"
  git init -q
  git commit --allow-empty -m "init" -q
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  cd /
  rm -rf "$SAGE_HOME" "$TEST_REPO"
}

# --- create --worktree ---

@test "create --worktree creates agent with git worktree" {
  cd "$TEST_REPO"
  run "$SAGE" create worker --worktree feature-auth
  [ "$status" -eq 0 ]
  # runtime.json should have worktree info
  run jq -r '.worktree' "$SAGE_HOME/agents/worker/runtime.json"
  [ "$output" = "true" ]
}

@test "create --worktree sets branch in runtime.json" {
  cd "$TEST_REPO"
  "$SAGE" create worker --worktree feature-auth
  run jq -r '.worktree_branch' "$SAGE_HOME/agents/worker/runtime.json"
  [ "$output" = "feature-auth" ]
}

@test "create --worktree agent workspace is a git worktree" {
  cd "$TEST_REPO"
  "$SAGE" create worker --worktree feature-auth
  local ws
  ws=$(jq -r '.workdir' "$SAGE_HOME/agents/worker/runtime.json")
  # The workspace should be a git worktree (has .git file, not directory)
  [ -f "$ws/.git" ]
}

@test "create --worktree fails outside git repo" {
  cd /tmp
  run "$SAGE" create worker --worktree feature-auth
  [ "$status" -ne 0 ]
  [[ "$output" =~ "git" ]]
}

@test "create --worktree fails with duplicate branch" {
  cd "$TEST_REPO"
  "$SAGE" create w1 --worktree feat-a
  run "$SAGE" create w2 --worktree feat-a
  [ "$status" -ne 0 ]
}

# --- rm with worktree ---

@test "rm cleans up git worktree" {
  cd "$TEST_REPO"
  "$SAGE" create worker --worktree feature-auth
  "$SAGE" rm worker
  # worktree should be removed
  run git worktree list
  [[ ! "$output" =~ "feature-auth" ]]
}

# --- merge ---

@test "merge command exists" {
  run "$SAGE" merge --help 2>&1
  # Should not be 'unknown command'
  [[ ! "$output" =~ "unknown command" ]]
}

@test "merge fails for non-worktree agent" {
  "$SAGE" create worker
  run "$SAGE" merge worker
  [ "$status" -ne 0 ]
  [[ "$output" =~ "worktree" ]]
}

@test "merge merges worktree branch back" {
  cd "$TEST_REPO"
  "$SAGE" create worker --worktree feat-x
  local ws
  ws=$(jq -r '.workdir' "$SAGE_HOME/agents/worker/runtime.json")
  # Make a commit in the worktree
  echo "hello" > "$ws/test.txt"
  git -C "$ws" add test.txt
  git -C "$ws" commit -q -m "add test"
  # Merge back
  run "$SAGE" merge worker
  [ "$status" -eq 0 ]
  # File should exist on main branch now
  [ -f "$TEST_REPO/test.txt" ]
}

# --- merge --dry-run ---

@test "merge --dry-run reports clean merge without merging" {
  cd "$TEST_REPO"
  "$SAGE" create worker --worktree feat-dr
  local ws
  ws=$(jq -r '.workdir' "$SAGE_HOME/agents/worker/runtime.json")
  echo "new" > "$ws/file.txt"
  git -C "$ws" add file.txt
  git -C "$ws" commit -q -m "add file"
  run "$SAGE" merge worker --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ "clean" ]]
  # File should NOT exist on main — dry-run doesn't merge
  [ ! -f "$TEST_REPO/file.txt" ]
}

@test "merge --dry-run detects conflicts" {
  cd "$TEST_REPO"
  "$SAGE" create worker --worktree feat-conflict
  local ws
  ws=$(jq -r '.workdir' "$SAGE_HOME/agents/worker/runtime.json")
  # Create conflicting changes
  echo "main-version" > "$TEST_REPO/clash.txt"
  git -C "$TEST_REPO" add clash.txt
  git -C "$TEST_REPO" commit -q -m "main change"
  echo "branch-version" > "$ws/clash.txt"
  git -C "$ws" add clash.txt
  git -C "$ws" commit -q -m "branch change"
  run "$SAGE" merge worker --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" =~ "conflict" ]]
}

@test "merge --dry-run shows diffstat on clean merge" {
  cd "$TEST_REPO"
  "$SAGE" create worker --worktree feat-stat
  local ws
  ws=$(jq -r '.workdir' "$SAGE_HOME/agents/worker/runtime.json")
  echo "data" > "$ws/stats.txt"
  git -C "$ws" add stats.txt
  git -C "$ws" commit -q -m "add stats"
  run "$SAGE" merge worker --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ "stats.txt" ]]
}

@test "merge --dry-run fails for non-worktree agent" {
  "$SAGE" create worker
  run "$SAGE" merge worker --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" =~ "worktree" ]]
}