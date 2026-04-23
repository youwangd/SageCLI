#!/bin/bash
# Reproducible kill-switch asciinema demo.
# Usage:
#   asciinema rec docs/kill-switch.cast -c "/home/dyouwang/SageCLI/docs/kill-switch-demo.sh"
#   /tmp/agg docs/kill-switch.cast docs/kill-switch.gif --cols 100 --rows 28
#
# Shows: 3 agents on 3 vendors → chaos-kill claude+gemini → sage fails over
# transparently to local Ollama. All primitives shipped in v1.4.0.

set -e
SAGE=/home/dyouwang/SageCLI/sage
# Fresh SAGE_HOME for reproducible demo. Copy real runtime shims over init's stubs.
export SAGE_HOME=$(mktemp -d)/sage-killswitch
$SAGE init >/dev/null 2>&1
cp -f "$HOME/.sage/runtimes/"*.sh "$SAGE_HOME/runtimes/" 2>/dev/null || true

say()  { printf '\033[1;36m# %s\033[0m\n' "$1"; sleep 2.2; }
run()  { printf '\033[1;32m$\033[0m %s\n' "$*"; sleep 0.8; "$@"; sleep 2.5; }
runL() { printf '\033[1;32m$\033[0m %s\n' "$*"; sleep 0.8; "$@"; sleep 3.5; }

printf '\033[2J\033[H'

say "Kill-switch drill: your primary AI vendor goes down. Workflow survives."
say "Why this matters: every other orchestrator is single-vendor-locked."

say "Step 1: Create 3 agents across 3 different vendors."
run $SAGE create reviewer-primary --runtime claude-code
run $SAGE create reviewer-gemini  --runtime gemini-cli
run $SAGE create reviewer-local   --runtime ollama --model llama3.2:3b

say "Step 2: Simulate cloud outage — mask Claude + Gemini from PATH."
_CLAUDE_DIR=$(dirname "$(command -v claude 2>/dev/null)" 2>/dev/null)
_GEMINI_DIR=$(dirname "$(command -v gemini 2>/dev/null)" 2>/dev/null)
_MASK=""
[[ -n "$_CLAUDE_DIR" ]] && _MASK="^$_CLAUDE_DIR$"
[[ -n "$_GEMINI_DIR" ]] && _MASK="${_MASK:+$_MASK|}^$_GEMINI_DIR$"
if [[ -n "$_MASK" ]]; then
  export PATH=$(echo "$PATH" | tr ':' '\n' | grep -vE "$_MASK" | paste -sd:)
fi
printf '\033[1;32m$\033[0m %s\n' "# claude & gemini binaries no longer on PATH"
sleep 2

say "Step 3: Send task with fallback chain. Primary = Claude (unreachable)."
SEND_OUT=$(mktemp)
$SAGE send reviewer-primary "Say HELLO in one word." \
  --fallback reviewer-gemini \
  --fallback reviewer-local 2>&1 | tee "$SEND_OUT"
sleep 3

say "Notice: sage pre-flight health-checked claude, gemini, then routed to ollama."
say "Same API, different vendor, zero user intervention."

# Wait for task to actually complete (ollama CPU first call: model load 15-20s + infer 3-8s)
TASK=$(grep -oE 't-[0-9]+-[0-9]+' "$SEND_OUT" | head -1)
for _ in $(seq 1 45); do
  s=$($SAGE result "$TASK" --json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('status','?'))" 2>/dev/null)
  [[ "$s" == "done" ]] && break
  sleep 2
done

say "Step 4: Retrieve the result — done on the local fallback."
printf '\033[1;32m$\033[0m sage result %s --json | jq -r .output\n' "$TASK"
sleep 0.8
$SAGE result "$TASK" --json 2>/dev/null | python3 -c "
import json,sys,re
d=json.load(sys.stdin)
out=re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]','',d.get('output',''))
out=re.sub(r'[\u2800-\u28ff]','',out).strip()
print(out[-300:] or '(task done — see sage logs)')
" 2>/dev/null || true
sleep 4

say "That's the vendor-neutrality moat. Only sage does this today."
sleep 3
