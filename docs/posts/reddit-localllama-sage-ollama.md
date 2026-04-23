# r/LocalLLaMA post — Sage v1.4.0 + Ollama orchestration

**Status**: READY TO POST
**Subreddit**: r/LocalLLaMA
**Type**: self-post (Text)
**Suggested flair**: `Resources` or `Tutorial | Guide`
**Best posting window**: weekday 08:00–11:00 US Pacific

---

## Title (locked)

```
Parallel multi-agent workflows with Ollama, in ~8500 lines of bash. Benchmarks inside.
```

---

## BODY — copy everything between the fences below into Reddit's text editor

<!-- CLIPBOARD-START -->
I've been working on **Sage** ([github.com/youwangd/SageCLI](https://github.com/youwangd/SageCLI)) — an AI agent orchestrator written in pure bash. No Python runtime, no Node server, no SaaS. Just bash, `jq`, and `tmux`. It can drive Claude Code, Codex, Gemini CLI, OpenCode, Cline, Kiro, **and Ollama / llama.cpp** from the same command surface.

I kept seeing the qwen3.6-35b + OpenCode threads here and thought: *"OK, but what if I want to run three local models in parallel and merge their outputs?"* Sage does that. Here's a real run on a **CPU-only** box (16-core Xeon, 62GB RAM, no GPU) using `llama3.2:3b`:

    $ sage create local-writer --runtime ollama --model llama3.2:3b
    $ sage create local-critic --runtime ollama --model llama3.2:3b
    $ sage create local-editor --runtime ollama --model llama3.2:3b

    $ sage send local-writer "Summarize in ONE sentence: why local LLMs matter."
    $ sage send local-critic "List 3 limitations of local LLMs."
    $ sage send local-editor "Recommend hardware for local LLMs. ONE sentence."

    $ # ... 34 seconds later, all three done
    $ sage result t-1776971675-20386   # fetch each agent's output

**Actual numbers from my box:**

* Model: `llama3.2:3b` (Q4, ~2GB)
* Hardware: 16-core Xeon, 62GB RAM, **no GPU**
* Raw ollama throughput: **13.81 tok/s** generation, 23.67 tok/s prompt eval
* 3 parallel `sage` agents end-to-end: **34 seconds**
* ollama CPU peak: 75% (one model instance, serializes internally)
* Resident memory (1 model loaded): ~2.4 GB
* Sage framework itself: ~8500 lines of bash, zero runtime deps beyond `jq` + `tmux`

**What "parallel" actually means here**

Honest caveat: ollama's default build serializes generation requests through one model instance. So three agents against one ollama server = 3x sequential inference under the hood. The *orchestration* is parallel (agents are independent, fan-out/collect works, would scale on multi-GPU), but the *inference* is serialized until you run multiple ollama instances or set `OLLAMA_NUM_PARALLEL=3` on the server.

Point each agent at a different model (writer→llama3.2:3b, critic→qwen3:8b, editor→phi-4) and you get mixed model families in one plan — still serialized on a single ollama server, truly parallel on multi-GPU.

**Why bash?**

Short: zero cold-start, zero dependency drift, zero "which Python env did I install this in". Every competitor in this space (claude-flow, gastown, emdash, mux) needs Node/Rust/Go/Python. Sage boots in <50ms and ships as one executable.

Long: coordinating 8+ different agent CLIs is mostly glue — spawning subprocesses, managing tmux sessions, passing JSON through pipes. Bash is genuinely good at that. The parts that would be painful (JSON manipulation, async waits) I do with `jq` and file-based signaling.

**What's in it (v1.4.0)**

* 8 runtimes: Claude Code, Codex, Gemini CLI, Cline, Kiro, Bash, **Ollama**, **llama.cpp** — plus any ACP-compatible agent
* `sage plan` — YAML multi-agent workflows with dependency waves
* `sage plan --pattern fan-out/pipeline/debate/map-reduce` — named swarm patterns
* `sage dashboard` — live TUI of all running agents
* MCP server support, skills registry, per-agent git worktrees, persistent sessions, cost tracking
* Agent chaining: `sage send A "task" --then B --then C`
* 53 commands, 928 bats tests, CI on Ubuntu + macOS

**Gotchas I hit while writing this post**

`qwen3:0.6b` pulled 11 days ago → `Error: 400 Bad Request: does not support generate` with ollama v0.18.2. The old manifest template is stale; re-pull fixes it (~600MB redownload). Small-model quirk, not a sage issue.

`llama3.2:3b` hallucinates the agent framework's syntax into its answers — you'll see outputs like `sage send mytask "..."` in the raw logs. That's the 3B model echoing its own system prompt. 8B+ models stop doing this. Trim your `instructions.md` aggressively for small models.

**Links**

* Repo: [github.com/youwangd/SageCLI](https://github.com/youwangd/SageCLI)
* 37-second demo GIF: [docs/demo.gif](https://github.com/youwangd/SageCLI/blob/main/docs/demo.gif)
* Architecture diagram: [docs/diagrams/architecture.svg](https://github.com/youwangd/SageCLI/blob/main/docs/diagrams/architecture.svg)

Happy to benchmark different model combos if people post specs. If qwen3.6-35b runs on your box, I'd love to see `sage plan --pattern debate` on it.
<!-- CLIPBOARD-END -->

---

## Pre-submit checklist

- [x] Repo is public (github.com/youwangd/SageCLI)
- [x] v1.4.0 shipped, numbers in post match README (~8500 lines, 53 commands, 928 tests, 8 runtimes)
- [x] Post draft in repo for audit
- [ ] Pick flair on submit form: `Resources` (safer) or `Tutorial | Guide` (more clicky)
- [ ] Submit as **text post**, not link post
- [ ] First 30 min after submit is make-or-break — stay online to reply

## Expected pushback → pre-canned replies

**"Why not use OpenCode?"**
> OpenCode is one agent. Sage runs multiple agents with different backends (or the same backend) and merges their output. Complementary — sage has an OpenCode runtime too.

**"Bash doesn't scale"**
> Correct. Scales fine to ~100 agents on one box, which is where the "one developer orchestrating work" use case tops out. Past that you want something else.

**"This is just tmux + ollama"**
> Partly. The value is the `plan` / `send --then` / `msg` / `context` / `mcp` surface on top of that, plus 928 tests that make sure it doesn't regress.

**"Show me a hard use case"**
> PR review pipeline: `sage plan --pattern fan-out "Review PR #123"` spawns reviewer + security-auditor + test-writer in parallel, merges findings. Works with any mix of local and cloud models.

**"Can I use it with [my model]?"**
> If ollama/llama.cpp can serve it, sage can drive it. Set `--model <name>` on create.

## What I'm explicitly NOT claiming

- "as good as Claude" — we orchestrate local models, not claim the models themselves are state of the art
- qwen3.6-35b tok/s numbers — didn't run it (<1 tok/s on this CPU box, not honest to quote)
- GPU benchmarks — don't have one
- Production-ready — 2 stars, 928 tests, not v1.0 battle-tested yet
