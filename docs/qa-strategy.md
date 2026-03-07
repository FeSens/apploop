# QA Strategy — Visual Polish & User Flow Verification

## Overview

The QA phase runs **after all features pass** and **before improvement mode**. It is a
systematic, screenshot-driven walkthrough of every user-facing flow in the app. The goal
is to catch visual regressions, layout issues, and UX rough edges that unit tests and
XCUITests cannot detect.

**QA is MANDATORY. The stop gate will block you until every flow is verified.**

## QA Report (`qa-report.json`)

The QA report tracks verification status. It is generated automatically from `features.json`
when the agent enters QA mode for the first time. Structure:

```json
{
  "generated_at": "2026-03-07T12:00:00Z",
  "status": "in_progress",
  "simulator_device": "iPhone 16 Pro",
  "flows": [
    {
      "id": "qa-001",
      "name": "Descriptive flow name",
      "features_covered": ["ui-001", "ui-002"],
      "steps": [
        {
          "action": "Launch the app",
          "expected": "Home screen visible with nav title",
          "screenshot": "screenshots/qa-001-step-01.png",
          "verified": true,
          "issues": ""
        }
      ],
      "checklist": {
        "no_overlapping_elements": true,
        "text_not_truncated": true,
        "buttons_fully_visible": true,
        "navigation_title_correct": true,
        "tab_bar_visible": true,
        "spacing_consistent": true,
        "accumulated_state_correct": false,
        "no_stale_data": false,
        "dark_mode_checked": false,
        "landscape_checked": false
      },
      "verified": false,
      "notes": ""
    }
  ]
}
```

### Field Definitions

| Field | Description |
|-------|-------------|
| `status` | `"in_progress"` or `"passed"` — overall QA status |
| `flows[].verified` | `true` when ALL steps verified AND checklist complete |
| `steps[].screenshot` | Path to screenshot file — MUST be populated |
| `steps[].verified` | `true` when screenshot reviewed and expected state confirmed |
| `steps[].issues` | Description of any issue found (empty if none) |
| `checklist` | Visual quality checks — all must be `true` to verify a flow |

## QA Workflow

### Phase 1: Generate QA Plan

When entering QA mode for the first time:

1. Read `features.json` — collect all features with `passes: true`
2. Group features into logical **user flows** (e.g., "onboarding flow", "main tab navigation", "settings flow")
3. For each flow, create steps based on the `test_steps` from the features it covers
4. Add a **cold launch** flow (app from killed state)
5. Add a **dark mode** pass for all critical screens
6. Add a **landscape orientation** check for key screens
7. Add an **extended usage / soak flow** (see Phase 2b below)
8. Write the plan to `qa-report.json`
9. Create the `screenshots/` directory

### Phase 2: Execute QA Flows

For EACH flow in `qa-report.json`:

1. **Build and install** the app in the simulator:
   ```bash
   xcodebuild build -project {{PROJECT_NAME}}.xcodeproj -scheme {{PROJECT_NAME}} \
     -sdk iphonesimulator -destination 'id={{SIMULATOR_UUID}}' \
     -derivedDataPath .build/derived
   xcrun simctl install {{SIMULATOR_UUID}} .build/derived/Build/Products/Debug-iphonesimulator/{{PROJECT_NAME}}.app
   ```

2. **Launch the app**:
   ```bash
   xcrun simctl launch {{SIMULATOR_UUID}} {{BUNDLE_ID}}
   ```

3. **For each step**:
   a. Perform the action (tap, swipe, navigate) using computer use
   b. Wait for the UI to settle (animations, loading states)
   c. Take a screenshot:
      ```bash
      xcrun simctl io {{SIMULATOR_UUID}} screenshot screenshots/qa-XXX-step-YY.png
      ```
   d. **Read the screenshot** with the Read tool — visually analyze it
   e. Check against the visual checklist (see below)
   f. Record the result in `qa-report.json`

4. **If an issue is found**:
   a. Record the issue in `steps[].issues`
   b. Fix the code
   c. Rebuild, reinstall, relaunch
   d. Re-verify the step — take a NEW screenshot
   e. Continue only when the step passes

5. **After all steps pass**: mark `flow.verified = true`

### Phase 2b: Extended Usage / Soak Testing

Some bugs only surface after sustained interaction — state accumulates, badges appear,
caches fill, lists grow, counters increment, and edge cases emerge that a single-pass
walkthrough will never hit. This phase simulates a real user session.

**MANDATORY: Every QA run must include at least one extended usage flow.**

1. **Use the app like a real user for an extended session** (not just one action per screen):
   - Create multiple items (5-10), not just one
   - Navigate back and forth between screens repeatedly
   - Perform the same action several times in a row (e.g., add, edit, delete, add again)
   - Let state build up: fill lists, trigger badge counters, accumulate history
   - Switch between tabs/sections multiple times mid-flow

2. **Specifically stress these patterns**:
   - **Accumulated state**: Add enough items that lists scroll, counters reach double digits, storage grows
   - **Repeated actions**: Do the same thing 3-5 times — create/delete cycles, toggle on/off repeatedly
   - **Navigation depth**: Go 3+ screens deep, then back, then deep again — check state is preserved
   - **Interruption recovery**: Mid-flow, go to a different tab, come back — is state preserved?
   - **Boundary values**: Empty states → one item → many items. Zero → max values in inputs
   - **Rapid interaction**: Tap quickly, don't wait for animations — does the UI stay consistent?

3. **Screenshot at key state milestones** (not just each step):
   - After first item created
   - After 5+ items exist (list scrolling, badges updated)
   - After a delete-and-recreate cycle
   - After navigating away and returning
   - After toggling a setting and observing downstream effects

4. **What to look for**:
   - Stale UI: data changed but the screen didn't update
   - Badge/counter drift: counts don't match actual items
   - Layout degradation: UI looks fine with 1 item, breaks with 10
   - State leaks: data from one screen bleeds into another
   - Memory/scroll position: returning to a list resets scroll unexpectedly
   - Zombie state: deleted items still appear somewhere, or actions reference removed data

5. **Record findings** in `qa-report.json` under the soak flow. Mark issues clearly.

### Phase 3: Final Verification

After all flows are verified:

1. Run the **full XCUITest suite** one final time
2. Take a final set of screenshots of the key screens
3. Set `qa-report.json` `status` to `"passed"`
4. Commit qa-report.json and all screenshots
5. The stop gate will detect QA passed and transition to improvement mode

## Visual Checklist

Apply this checklist to EVERY screenshot. All items must pass.

### Layout & Structure
- [ ] Navigation title visible and not overlapping content
- [ ] Tab bar fully visible (not hidden behind content)
- [ ] No elements overlapping or clipped at screen edges
- [ ] Safe area respected (content not under notch/dynamic island)
- [ ] Scroll views have correct content insets

### Typography & Readability
- [ ] Text is not truncated (check long strings)
- [ ] Font sizes are readable (minimum 11pt for body text)
- [ ] Text contrast meets accessibility standards (4.5:1 ratio)
- [ ] Labels aligned consistently

### Interactive Elements
- [ ] Buttons are fully visible and have adequate tap targets (44x44pt minimum)
- [ ] Interactive elements have visual feedback states
- [ ] Form fields are not hidden behind keyboard
- [ ] Disabled states are visually distinct

### Spacing & Alignment
- [ ] Consistent margins and padding
- [ ] List items evenly spaced
- [ ] No unexpected gaps or cramped sections
- [ ] Content centered where appropriate

### State Verification
- [ ] Empty states display helpful messages
- [ ] Loading states show indicators
- [ ] Error states are informative and actionable
- [ ] Success states provide clear feedback

### Dark Mode (dedicated pass)
- [ ] All text readable against dark backgrounds
- [ ] No hard-coded colors causing contrast issues
- [ ] Images and icons adapt to dark mode
- [ ] Separators and borders visible

### Accumulated State & Extended Use
- [ ] Lists display correctly with 10+ items (scrolling, no clipping)
- [ ] Badges and counters reflect actual data after add/delete cycles
- [ ] Navigating away and back preserves screen state (scroll position, selections)
- [ ] Repeated create/delete cycles don't leave ghost data
- [ ] Settings changes propagate to all affected screens
- [ ] No stale data displayed after mutations (UI refreshes correctly)

### Landscape (key screens only)
- [ ] Layout adapts without breaking
- [ ] No content cut off on shorter height
- [ ] Navigation still accessible

## Screenshot Naming Convention

```
screenshots/
  qa-{flow_id}-step-{step_number}.png    # Flow step screenshots
  qa-{flow_id}-dark-{step_number}.png    # Dark mode variants
  qa-{flow_id}-landscape-{step_number}.png  # Landscape variants
  qa-final-{screen_name}.png             # Final verification shots
```

## Common Issues & Fixes

| Issue | Likely Cause | Fix |
|-------|-------------|-----|
| Nav title overlaps content | Large title mode | `.navigationBarTitleDisplayMode(.inline)` |
| Button behind tab bar | No bottom padding | Add `.safeAreaInset(edge: .bottom)` or use `VStack` with spacer |
| Text truncated | Fixed frame | Use flexible layout, `.lineLimit(nil)` |
| Keyboard hides input | No scroll adjustment | Wrap in `ScrollView` or use `.scrollDismissesKeyboard()` |
| Dark mode invisible text | Hard-coded color | Use semantic colors (`Color.primary`, `Color.secondary`) |
| Landscape breaks layout | Fixed height | Use `GeometryReader` or flexible frames |
| Stale data after mutation | Missing observation | Ensure `@Query` or `@Observable` triggers re-render |
| Badge count wrong | Derived state not updated | Recompute counts from source of truth, not cached values |
| List breaks with many items | Fixed height container | Use `List` or `LazyVStack` inside `ScrollView` |
| Ghost items after delete | Stale reference | Ensure SwiftData deletes propagate, use `@Query` auto-refresh |
| Scroll position lost | View identity changes | Use stable IDs in `ForEach`, avoid unnecessary re-renders |

## Integration with Stop Gate

The stop gate checks QA status in this order:

1. Any features failing? → **Features Failing** state (implement features)
2. All features pass, no `qa-report.json` or `status != "passed"`? → **QA Mode** (run QA)
3. All features pass AND `qa-report.json` `status == "passed"`? → **Improvement Mode**

The agent cannot skip QA. The stop gate enforces this automatically.
