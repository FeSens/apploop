# Stop Gate Prompts

Edit these prompts to customize what the agent sees when the stop gate blocks it.
Prompts are extracted from fenced code blocks (```) under each heading.

## Features Failing

This prompt is shown when there are still incomplete features. Template variables:

- `{{PASSING}}` — number of passing features
- `{{TOTAL}}` — total number of features
- `{{ACTIONS}}` — list of immediate issues (build failures, test failures, etc.)
- `{{NEXT_PROMPT}}` — details about the next feature + parallel batch info + blocked features

The `{{NEXT_PROMPT}}` variable now includes:
- The next feature to implement with test steps
- If multiple features are ready: a `PARALLEL READY` section listing them
- Blocked features and what they're waiting on

```
STOP BLOCKED - Progress: {{PASSING}}/{{TOTAL}} features passing.
{{ACTIONS}}
{{NEXT_PROMPT}}

PARALLELIZATION: If PARALLEL READY features are listed above, spawn feature-builder subagents
in worktrees to implement them simultaneously. See docs/parallel-development.md for the full
orchestration protocol. Use `python3 scripts/dependency-graph.py --ready` for the dependency analysis.
DO NOT STOP. Continue working.
```

## QA Mode

This prompt is shown when all features pass but QA verification is incomplete.
The agent must follow docs/qa-strategy.md to complete the QA phase. Template variables:

- `{{QA_VERIFIED}}` — number of verified flows
- `{{QA_TOTAL}}` — total number of flows (0 if plan not yet generated)
- `{{QA_NEXT_FLOW}}` — ID of the next unverified flow
- `{{QA_NEXT_NAME}}` — name of the next unverified flow
- `{{QA_NEXT_STEPS_DONE}}` — steps completed in current flow
- `{{QA_NEXT_STEPS_TOTAL}}` — total steps in current flow
- `{{QA_NEXT_CHECKS}}` — checklist progress (e.g., "3/8")

```
ALL FEATURES PASSING. Entering QA MODE — visual polish and user flow verification.

Read docs/qa-strategy.md for the full QA protocol.

QA Progress: {{QA_VERIFIED}}/{{QA_TOTAL}} flows verified.

NEXT FLOW: {{QA_NEXT_FLOW}} — {{QA_NEXT_NAME}} (steps: {{QA_NEXT_STEPS_DONE}}/{{QA_NEXT_STEPS_TOTAL}}, checklist: {{QA_NEXT_CHECKS}})

QA PROTOCOL:
1. If qa-report.json does not exist, generate it from features.json (see docs/qa-strategy.md)
2. Build, install, and launch the app in the simulator
3. For EACH step in the current flow:
   a. Perform the action using computer use
   b. Take a screenshot: xcrun simctl io {{SIMULATOR_UUID}} screenshot screenshots/<name>.png
   c. Read the screenshot with the Read tool — METICULOUSLY analyze it top-to-bottom, edge-to-edge
   d. OVERLAP CHECK (most missed issue): Scan the bottom 20% of the screen — do ANY elements
      overlap the tab bar, home indicator, or each other? Check every boundary where two UI
      regions meet (nav bar/content, content/tab bar, content/keyboard, button/tab bar).
      If any element crosses into another's region, it is a FAIL. Fix it before moving on.
   e. Evaluate against the FULL visual checklist (layout, typography, spacing, buttons, dark mode)
   f. If issues found: fix the code, rebuild, re-screenshot, re-verify
   g. Update qa-report.json with screenshot path and verified status
4. After all steps pass, complete the flow checklist and mark flow as verified
5. Move to the next unverified flow
6. MANDATORY SOAK TEST: Use the app like a real user — create many items, navigate back and
   forth, repeat actions, let state accumulate. Bugs often only appear after multiple interactions
   (badges drift, lists break with many items, stale data, state leaks between screens).
   Screenshot at state milestones (after 5+ items, after delete cycles, after nav round-trips).
   See docs/qa-strategy.md Phase 2b for the full soak protocol.
7. After ALL flows verified (including soak): run full XCUITest suite, set qa-report.json status to "passed", commit

Screenshots are MANDATORY at every step. Never skip a screenshot.
DO NOT ask the user for input. Execute the QA plan autonomously.
DO NOT STOP. Continue QA verification.
```

## All Passing (QA Complete)

This prompt is shown when all features pass AND QA is verified. The agent enters improvement mode.

```
ALL FEATURES PASSING. QA VERIFIED. Enter improvement mode:

1. Review the app for UX polish opportunities
2. Search for best practices and competitive analysis
3. Add 3-5 new improvement features to features.json with passes: false
4. Start implementing them using the TDD loop

When new features are added, qa-report.json will be reset automatically on next QA cycle.
DO NOT ask the user for input. Research, plan, and execute autonomously.
```
