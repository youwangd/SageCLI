# Show HN: Submission Plan

**Target date**: Tue–Thu, 9–11am ET (peak HN traffic)
**Link**: https://github.com/youwangd/SageCLI (repo, not the blog post — HN conversion is better off README than off prose)
**Text**: leave blank (link post only — HN algorithm slightly favors link-only Show HN for tooling)

## Title — pick one before submitting

All under the 80-char HN limit. Leading with the kill-switch differentiator since "pure bash orchestrator" alone already flopped with "Orc" on 2026-03-19 (2 points).

### Option A (recommended) — kill-switch lead
```
Show HN: Sage – your Claude Code workflow survives an Anthropic outage
```
77 chars. Concrete pain point → concrete solution. Non-coders can parse it.

### Option B — portability lead
```
Show HN: Sage – one bash script orchestrates Claude Code, Gemini CLI, Codex
```
78 chars. Safer but closer to Orc's framing — higher flop risk.

### Option C — bench lead
```
Show HN: Sage – I benchmarked Claude Code vs Gemini vs local models. Here's the tool
```
84 chars (2 over — trim: "Show HN: Sage – benchmarked Claude Code vs Gemini vs local. Here's the tool")
Data-led titles do well on HN but it's a weaker hook if you haven't read the post.

### Option D — vendor-neutrality explicit
```
Show HN: Sage – vendor-neutral orchestrator for 8 AI CLIs (Claude Code, Codex, Gemini...)
```
93 chars — too long. Not recommending.

**Go with A.**

## Opening comment (post immediately after submission)

HN tradition: submitter posts the first comment with context. Keep it short, human, no marketing language.

```
Hi HN,

I built sage because I kept running into the same problem: my entire PR-review
workflow ran on Claude Code, and every time Anthropic had a degradation window
my team just sat on their hands. Single point of failure.

Sage wraps 8 agent CLIs (Claude Code, Gemini CLI, Codex, Cline, Kiro, Ollama,
llama.cpp, plus any ACP agent) behind one command surface. The failover case
looks like this:

    sage send reviewer "Review src/main.py" \
      --fallback reviewer-gemini \
      --fallback reviewer-local

Pre-flight health check on the primary runtime. If the binary isn't reachable
or the daemon isn't responding, tries each fallback in order. Same command
works whether the agent is Claude Code, Gemini CLI, or a local llama3.2:3b
via ollama.

Implementation constraints I held:
- One bash script, 8,500 lines. No Python, no Node, no Go runtime.
- Deps: bash 4+, jq, tmux. That's it.
- Every primitive works across all 8 runtimes (928 bats tests enforce this).
- JSON in, JSON out. stdin/stdout. Pipes cleanly with jq and the rest.

A companion write-up on why I think portable orchestration beats locked-in
orchestration (and why proxy solutions like claude-code-router solve the wrong
problem) is here:
https://github.com/youwangd/SageCLI/blob/main/docs/posts/portable-orchestration.md

I also ran `sage bench run` on the repo itself — 5 tasks × 3 agents across
Claude Code / llama3.2:3b / echo-baseline — and the results surprised me.
Full methodology and honest caveats:
https://github.com/youwangd/SageCLI/blob/main/docs/use-case-bench.md

Happy to take questions on the design decisions, the bash-only constraint,
or why I didn't just put a proxy in front of everything.
```

**Length**: ~220 words. Within the "short enough to scan, long enough to earn interest" band.

## Reply templates — for predictable HN comment classes

Prepare these so you're not typing at 2am when the thread is hot.

### "Why bash?"
```
Three reasons, in order of how much they actually mattered:

1. Install friction. curl|bash and it works. No venv/nvm/rust toolchain.
   Every competitor here requires Node or Python. Ship in CI, airgapped
   boxes, ephemeral containers.
2. Each runtime is just a subprocess with a known wire format. Python/Go
   wouldn't help — the work is string parsing and process plumbing.
3. Forcing the constraint exposed the design. If I couldn't do it in bash,
   I was probably over-engineering. The whole thing is 8,500 lines in one
   file; you can read it in an afternoon.

The downside is real: some control flow is ugly, and I've had two subtle
bugs from bash's scoping rules. If you're allergic to bash this is probably
not the tool for you.
```

### "Why not just use claude-flow / claude-code-router / ruflo?"
```
Claude-flow is locked to Anthropic. Ruflo added Codex last month, still
primarily Anthropic. If Anthropic changes a flag or has an outage, your
workflows break.

claude-code-router is a proxy — it translates at the API level, which means
it re-creates the CLI on top of the model API. You lose prompt caching,
native auth flows, and retry logic, and you add a new point of failure
(the proxy itself). See the post at
github.com/youwangd/SageCLI/blob/main/docs/posts/portable-orchestration.md
for why I think that's the wrong layer to swap.

Sage is the same orchestration model as claude-flow, but runtime-agnostic.
Adding a new CLI is one file with two functions.
```

### "Is this just another agent framework?"
```
No — I deliberately don't ship agents. Sage is the control plane under
Claude Code / Codex / Gemini CLI etc. It doesn't write code. It doesn't
ship prompts. It coordinates the CLIs that do. See docs/POSITIONING.md.
```

### "How do you handle <vendor X>'s quirk?"
```
Each runtime is one file in ~/.sage/runtimes/ with two functions
(runtime_start + runtime_inject). Happy to walk through a specific one —
which vendor?
```

### "The bench results look unfair — Claude Code took 40s for 'what is 7×8?'"
```
Completely fair criticism. The bench tests trivial prompts, which is
exactly where coding-agent CLIs are penalized (their scaffolding cost
dominates wall-time when the actual work is 2 lines). For real coding
tasks Claude Code almost certainly wins. The point of bench isn't
"local models beat Claude" — it's "run your actual workload to find
out, because no vendor blog will tell you."

Full caveats in the post:
github.com/youwangd/SageCLI/blob/main/docs/use-case-bench.md
```

### "Why 8,500 lines in one file?"
```
Started life at 5,150 lines a year ago. Grew with scope. I've audited
it for split-ability — 3 of the 61 functions are >200 lines (plan_execute
is the worst at 320L, nesting depth 18). Those are on the refactor list.
The rest are small; ~75% of functions are ≤100 lines. It's one file because
sourcing 15 sub-files in bash adds load-time complexity for no real
testability gain when you already have 928 bats tests.

Not defending it as beautiful. Defending it as honest about what it is.
```

## Post-launch protocol

### Hour 0–2 (submission → first comments)
- Submit at 9:00am ET, post opening comment within 60s
- Stay at the keyboard for the first 2 hours. Reply to every substantive comment within 15 min.
- If karma ticks up slowly, that's fine — HN new queue moves slowly for the first hour.
- If thread gets no comments by hour 1, flag #channel-2 for Reddit cross-post (below)

### Hour 2–12
- Reply turnaround can relax to ~60 min
- Flag patterns in the comments — those are material for follow-up posts

### Day 2 — Reddit cross-post
If HN went well: title angle at r/commandline = "Zero-dep bash orchestrator"
If HN flopped: same title but at r/commandline with a different framing ("open source weekend project, feedback welcome")

### Day 3–5 — lobste.rs (if invite available)
Higher bar, smaller audience, but the right crowd for the bash/Unix angle.

## Pre-flight checklist

Run the drill before submitting:

- [ ] README reads well for first-time visitor (scroll it top-to-bottom, cold)
- [ ] `install.sh` actually works (test in fresh docker container)
- [ ] `brew tap youwangd/sage` actually works (verify tap exists)
- [ ] kill-switch GIF plays in README
- [ ] bench table numbers match what's in docs/use-case-bench.md
- [ ] No broken links in README (markdown link checker)
- [ ] Issues tab open, not locked
- [ ] CI badges green
- [ ] You have 4–6 uninterrupted hours to babysit the thread
