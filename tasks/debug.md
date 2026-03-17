---
name: debug
description: Debug a reported issue — reproduce, diagnose, fix
input: description
output: structured
parallel: false
runtime: acp
---

# Debugging

You are debugging a reported issue. Your job: reproduce it, find the root cause, fix it, and verify the fix.

## Process

1. **Understand the report.**
   - What's the expected behavior?
   - What's the actual behavior?
   - What are the reproduction steps?
   - When did it start? What changed recently?

2. **Reproduce first.** Before diagnosing:
   - Follow the reported steps exactly
   - Confirm you can see the same failure
   - If you can't reproduce, try variations (different inputs, timing, environment)
   - If still can't reproduce, report that with what you tried

3. **Narrow down the cause.**
   - Add logging or print statements at key boundaries
   - Check recent git history for relevant changes (`git log --oneline -20`, `git diff`)
   - Bisect if needed: what's the last known working state?
   - Read error messages carefully — the actual error is often buried in a stack trace
   - Check: is it a code bug, a data issue, a configuration problem, or an environment issue?

4. **Identify root cause.** Don't just find WHERE it fails. Find WHY it fails.
   - "It crashes on line 42" is not a root cause
   - "Line 42 assumes `user.email` is never null, but the OAuth flow creates users without email" is a root cause

5. **Fix it.**
   - Fix the root cause, not the symptom
   - Consider: are there other places with the same bug? (Same pattern, same assumption)
   - Write a test that reproduces the bug FIRST, then fix the code so the test passes
   - Run the full test suite to make sure the fix doesn't break anything else

6. **Verify.**
   - Confirm the original reproduction steps no longer show the bug
   - Confirm the new test passes
   - Confirm existing tests still pass

## Output Format

```
## Bug Report
- Issue: [one-line summary]
- Reported behavior: [what was wrong]
- Expected behavior: [what should happen]

## Root Cause
[Explanation of WHY the bug exists, not just where]

## Fix
- Files modified: [list]
- What changed: [brief description]
- Test added: [yes/no, test name]

## Verification
- Original issue: [FIXED / NOT FIXED]
- Test suite: [PASS / FAIL with details]
- Related issues found: [any other instances of the same bug pattern]
```

## Rules

- Always reproduce before diagnosing. Assumptions about bugs are wrong more often than they're right.
- Fix the root cause. Band-aids create more bugs later.
- One fix per bug. Don't sneak in refactoring or feature changes.
- If you can't find the root cause after thorough investigation, say so. Report what you've ruled out.
