# Use Case: Bench-as-Code

## The problem

You're an engineering lead. You have $10K/month of AI budget. Should you
buy Claude Code seats, Gemini CLI subscriptions, or run qwen3 on your own
GPU box? Nobody can tell you:

- **Vendor benchmarks** test models on MMLU, HumanEval, SWE-Bench. Those
  aren't your workflow.
- **Community benchmarks** compare raw API calls. But you don't use raw
  APIs — you use the **agent CLI** (Claude Code, Codex, etc.), which adds
  its own scaffolding, tool-use loops, permission prompts, and cost.
- **Vendor blog posts** are biased.

What you actually need is to run **your actual tasks** through **each
vendor's actual agent CLI** and get a decision-ready comparison.

## The sage answer

    sage bench run ./bench-tasks --agents claude-code-agent,gemini-agent,ollama-agent
    sage bench report --format markdown

One command dispatches each task file to each agent, waits for completion,
records wall-time + success, and produces a table you can put in a
planning doc.

No other orchestrator can do this today, because no other orchestrator
drives all the agent CLIs from one command surface. Every vendor CLI has
its own invocation format, output format, error handling — sage's runtime
shims normalize all of that behind a single `sage send` API. `sage bench`
is the natural consequence.

## How it works

1. **Task files**: put a `.prompt` file per test case in a directory.
2. **Agents**: create one sage agent per vendor/model you want to compare.
3. **Dispatch**: `sage bench run` sends each prompt to each agent in
   sequence (parallel across agents coming in v2), polling for completion.
4. **Oracle**: by default `--oracle exit-zero` counts any task that
   finishes with status `done` as success. `--oracle file-diff` compares
   output to a golden file for strict pass/fail.
5. **Report**: markdown/csv/json with per-agent summary + task×agent matrix.

Results are stored as JSONL in `~/.sage/bench/<run-id>/results.jsonl` —
reproducible, diffable, pipeable.

## Real dogfood results

Run on 2026-04-24, CPU-only Cloud Desktop (16-core Xeon, 62GB RAM, no GPU):

    sage bench run bench-tasks \
      --agents bench-claude,bench-ollama,bench-echo \
      --timeout 300

5 tasks (hello / list / math / code-review / JSON output) × 3 agents:

| Agent        | Tasks | Success | Success rate | Median wall (ms) |
|--------------|-------|---------|--------------|------------------|
| bench-claude | 5     | 3       | 60.0%        | 46,268           |
| bench-ollama | 5     | 5       | 100.0%       | 2,577            |
| bench-echo   | 5     | 0       | 0.0%         | 2,057            |

Per task:

| Task           | bench-claude   | bench-ollama   |
|----------------|----------------|----------------|
| 01-hello       | 24,685 ms ✓    | 2,577 ms ✓     |
| 02-list        | 46,268 ms ✓    | 2,058 ms ✓     |
| 03-math        | 34,252 ms ✓    | 2,057 ms ✓     |
| 04-code-review | 301,576 ms ✗   | 26,213 ms ✓    |
| 05-json        | 301,666 ms ✗   | 14,153 ms ✓    |

## What these numbers mean — and what they don't

Be careful how you read this.

### What the report DOES measure

- **End-to-end agent-orchestration latency**: the time from "sage dispatched
  a task" to "sage has a final answer". This includes the vendor CLI's
  startup cost, tool-use loops, permission prompts, and anything else the
  agent does between prompt and reply.
- **Reliability under a reasonable timeout**: does the agent finish within
  5 minutes for a simple prompt?
- **Deterministic success signal**: did it complete the task loop
  (exit-zero oracle) or match a golden output (file-diff oracle)?

### What the report does NOT measure

- **Raw model quality.** When both agents completed, both produced correct
  outputs. Claude Code is absolutely capable of the code-review task — it
  just times out here because its tool-use loop explores the filesystem
  looking for context before answering.
- **Production suitability.** Claude Code is optimized for long-form
  coding sessions with rich tool use. Putting it in a tight bench loop
  with trivial prompts is the wrong use of the tool. A 30-minute
  refactoring session will look very different.
- **Cost.** Wall-time is a proxy for cost but not a substitute. Ollama
  costs ~$0 on already-owned hardware; Claude Code burns API tokens. Token
  counting per agent is Phase 22 roadmap work.

### The actual lesson

For **trivial orchestration tasks** (quick lookups, summaries, classifiers,
simple code checks), **a small local model on CPU beats a full coding
agent CLI** — not because the local model is smarter, but because the
coding agent's scaffolding cost dominates the wall-time for short tasks.

Before this data, the default assumption would be "Claude is best, just
pay for it." After this data, the question becomes: *"what fraction of my
workflow is actually complex enough to justify Claude's overhead, versus
what fraction is better served by a local model?"*

That's a useful question. No vendor benchmark will ever frame it for you.

## Running it yourself

### Quick try

    # Clone + init
    git clone https://github.com/youwangd/SageCLI
    cd SageCLI && ./sage init

    # Create agents for whatever you have installed
    ./sage create bench-ollama --runtime ollama --model llama3.2:3b
    ./sage create bench-claude --runtime claude-code          # if you have claude
    ./sage create bench-gemini --runtime gemini-cli           # if you have gemini

    # Run against shipped tasks
    ./sage bench run bench-tasks --agents bench-ollama,bench-claude --timeout 300
    ./sage bench report

### Bring your own tasks

Any directory of `.prompt` files will work:

    mkdir my-tasks
    echo "Explain what this commit does: $(git log -1 --format=%B)" > my-tasks/01.prompt
    echo "Review src/main.py for security issues" > my-tasks/02.prompt
    # ...
    sage bench run my-tasks --agents claude,gemini,ollama

### Custom success oracle

For strict grading, put golden outputs alongside prompts:

    tasks/01.prompt           # the prompt
    tasks/01.golden           # expected output (exact match after trim)

    sage bench run tasks --agents ... --oracle file-diff --golden tasks

## What's next (v2)

- **Parallel dispatch** — currently tasks run sequentially. Parallelize
  across agents so wall-clock for N agents ≈ max(agent_latency), not sum.
- **Token + cost tracking** — capture `sage stats` per agent during the
  run, include $/token and $/task in the report.
- **`--oracle llm-judge`** — a separate synthesizer agent reads the
  output and grades it (useful for open-ended tasks).
- **Pattern support** — `--patterns single,debate,pipeline` to compare
  "one agent" vs "three-agent debate" on the same tasks.
- **`sage stats --fallbacks`** — track how often kill-switch fired per
  vendor, feed into the same report.

## Why this matters strategically

Every other orchestrator picks a vendor. claude-flow optimizes for Claude,
ruflo optimizes for Claude+Codex, emdash optimizes for Claude. None of
them can benchmark their chosen vendor against the alternative — they
literally don't support the alternative.

Sage's 8 runtime shims turn from a maintenance cost into a **measurement
apparatus**. Every time Anthropic ships a new Claude version, every time
Google updates Gemini CLI, every time a new open-weight model drops on
HuggingFace — sage can re-run the same bench, produce a fresh report, and
tell you if your budget assumptions still hold.

That's a moat. It gets wider every time the industry fragments further.

## Related

- [POSITIONING.md](POSITIONING.md) — why sage exists, what it is and isn't
- [use-case-kill-switch.md](use-case-kill-switch.md) — the other neutrality-moat demo
- `bench-tasks/` in the repo — the 5 dogfood tasks + real reports
