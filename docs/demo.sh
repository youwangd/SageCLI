#!/bin/bash
# Reproducible demo script for asciinema.
# Usage:
#   cd /tmp && asciinema rec /home/dyouwang/SageCLI/docs/demo.cast -c "/home/dyouwang/SageCLI/docs/demo.sh"
#
# Records sage init → demo → ls → plan YAML → acp ls in a clean SAGE_HOME.

set -e
export SAGE_HOME=$(mktemp -d)/sage-demo
SAGE=/home/dyouwang/SageCLI/sage

# Typing-speed helpers so the cast isn't a wall of instant text
# Tuned for GIF viewers who need reading time — not live terminal users
say()  { printf '\033[1;36m# %s\033[0m\n' "$1"; sleep 2.2; }
run()  { printf '\033[1;32m$\033[0m %s\n' "$*"; sleep 0.8; "$@"; sleep 2.5; }
runL() { printf '\033[1;32m$\033[0m %s\n' "$*"; sleep 0.8; "$@"; sleep 4.0; }  # long-output commands

# Clear screen (portable — works with and without a real TTY)
printf '\033[2J\033[H'
say "sage — pure bash AI agent orchestrator (zero frameworks, zero deps beyond bash/jq/tmux)"
sleep 0.5

run "$SAGE" --version
run "$SAGE" init

say "sage demo scaffolds a working 3-agent fan-out example"
runL "$SAGE" demo

say "Three agents created, ready to review code in parallel:"
run "$SAGE" ls

say "And a plan YAML wired up for fan-out execution:"
runL cat "$SAGE_HOME/plans/demo-fan-out.yaml"

say "sage acp ls — discover agents from the ACP Registry (live)"
printf '\033[1;32m$\033[0m %s\n' "$SAGE acp ls | head -12"
sleep 0.8
"$SAGE" acp ls 2>/dev/null | head -12
sleep 4.5

say "That's it. 53 commands, 8 runtimes, 928 tests. Pure bash."
sleep 4
