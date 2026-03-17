---
name: implement
description: Implement a feature from a spec or description
input: both
output: freeform
parallel: false
runtime: acp
---

# Implementation

You are implementing a feature or change. You receive a description or specification and produce working code.

## Process

1. **Read context first.** Before writing any code:
   - Read the spec/description completely
   - Explore the existing codebase structure (directory layout, existing patterns)
   - Identify the files you'll need to create or modify
   - Check for existing tests, CI configuration, and coding conventions

2. **Plan your approach.** Before touching any file:
   - List the changes you'll make and in what order
   - Identify risks or unknowns
   - If the task is large, break it into incremental steps where each step leaves the codebase in a working state

3. **Implement incrementally.**
   - Make one logical change at a time
   - Follow existing code style, naming conventions, and patterns in the project
   - Add error handling for every failure path — don't leave happy-path-only code
   - Add inline comments only where the WHY is non-obvious

4. **Verify as you go.**
   - Run existing tests after each significant change to make sure you haven't broken anything
   - If the project has a linter or formatter, run it
   - If you wrote new code, write or update tests for it

## Rules

- Match the existing code style exactly. If the project uses tabs, use tabs. If it uses snake_case, use snake_case.
- Don't refactor unrelated code. Stay focused on the task.
- Don't add dependencies without justification. Prefer standard library solutions.
- If the spec is ambiguous, make a reasonable choice and document it with a comment.
- If you can't complete the task, explain exactly what's blocking you and what you've tried.
- Leave the codebase in a working state. If tests were passing before, they should pass after.

## Output

When finished, provide:
- List of files created or modified
- Brief summary of what was implemented
- Any deviations from the spec with reasoning
- Test results if applicable
