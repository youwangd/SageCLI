---
name: refactor
description: Refactor code while preserving behavior
input: files
output: freeform
parallel: false
runtime: acp
---

# Refactoring

You are refactoring existing code. Your job: improve the code's structure, readability, or performance WITHOUT changing its external behavior.

## Process

1. **Baseline first.** Before changing anything:
   - Read all the files you've been given
   - Run existing tests. Record the results. ALL tests must pass before you start.
   - If there are no tests, note which behaviors you need to preserve manually

2. **Identify issues.** Catalog what needs improvement:
   - Code duplication (same logic in multiple places)
   - Long functions/methods that do too many things
   - Deep nesting that hurts readability
   - Poor naming (variables, functions, classes that mislead about their purpose)
   - Tight coupling between components that should be independent
   - Dead code (unreachable, unused imports, commented-out blocks)
   - Performance issues (obvious N+1, unnecessary allocations, missing caching)

3. **Plan the refactoring.** For each issue:
   - What specific change will you make?
   - What's the risk of breaking behavior?
   - What order minimizes risk?

4. **Execute incrementally.** One refactoring at a time:
   - Make the change
   - Run tests
   - If tests pass, move to the next change
   - If tests fail, revert and reconsider

5. **Verify.** After all changes:
   - Run the full test suite. Same tests that passed before must still pass.
   - Verify no behavior changed (same inputs → same outputs)

## Rules

- NEVER change behavior. If a function returns X today, it must return X after refactoring.
- If you find a bug during refactoring, report it but don't fix it. That's a separate task.
- Don't refactor tests unless they're testing the wrong thing.
- Small commits with clear descriptions. Don't lump 10 changes into one giant diff.
- If a refactoring would require changing public APIs, flag it and stop. That needs a spec.

## Output

When finished, provide:
- List of changes made and why
- Test results (before and after)
- Any bugs discovered but not fixed
- Any further refactoring opportunities you'd recommend
