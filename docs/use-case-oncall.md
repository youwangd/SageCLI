# Use Case: Multi-Ticket Oncall Orchestration

## Overview

Use Sage to orchestrate multiple Kiro agents for parallel ticket resolution. One interactive Kiro session (orch) manages N sub-agents, each handling one ticket with browser + bash tools.

## Architecture

```
You (terminal)
  ↕ direct conversation
Kiro (orch, interactive)
  ↕ sage CLI commands
5× Kiro sub-agents (ACP, background)
  ↕ browser + bash + file tools
Ticketing system (Jira, GitHub Issues, etc.)
```

Key: You only talk to orch. Orch uses sage to manage sub-agents mechanically. Sub-agents write output to disk. Orch reads via `sage peek`.

## Quick Start

```bash
# 1. Copy the orch prompt
cp prompts/oncall-orch.md ./ORCH.md

# 2. Start Kiro as orchestrator
kiro "Read ORCH.md. You are the oncall orchestrator."

# 3. Give it tickets
> 5 tickets:
> JIRA-123: Login fails after password reset
> JIRA-456: API /users timeout at 50+ users
> JIRA-789: Missing department field
> JIRA-012: Crash on empty form submit
> JIRA-345: Discount off by 1 cent

# 4. Check progress
> check

# 5. Give instructions based on findings
> approve 123 and 345, ask 789 about nullable

# 6. Check again
> check

# 7. Cleanup when done
> done
```

## How It Works Under the Hood

### Orch creates sub-agents:
```bash
sage create oncall-123 --runtime acp --agent kiro
sage send oncall-123 "You are assigned to JIRA-123: Login fails after password reset..."
```

### Orch checks sub-agents:
```bash
sage peek oncall-123 --lines 20
# Returns last 20 lines of agent output from ~/.sage/agents/oncall-123/.live_output
```

### Orch routes your instructions:
```bash
sage send oncall-123 "Human approved: apply the session token fix and resolve."
```

### Cleanup:
```bash
sage stop oncall-123
sage rm oncall-123
```

## Data Flow

```
~/.sage/agents/
├── oncall-123/
│   ├── inbox/          ← sage send writes here
│   ├── .live_output    ← agent streams output here
│   ├── results/        ← completed task results
│   └── runtime.json    ← agent config (acp, kiro)
├── oncall-456/
│   └── ...
└── oncall-789/
    └── ...
```

All state is files. `sage peek` reads files. `sage send` writes files. No session attachment needed.

## Why Sage (Not Pure Kiro)

- **Mechanical agent lifecycle** — create/stop/remove via bash, not LLM decisions
- **File-based state** — every agent's output on disk, queryable anytime
- **Trace logging** — every `sage send` logged in `~/.sage/trace.jsonl`
- **Parallel agents** — sage manages N background ACP processes
- **Human stays in one terminal** — talk to orch, orch manages the rest
