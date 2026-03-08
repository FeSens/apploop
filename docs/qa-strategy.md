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
        "bottom_region_clear": false,
        "no_tab_bar_overlap": false,
        "no_zorder_conflicts": false,
        "text_not_truncated": true,
        "buttons_fully_visible": true,
        "navigation_title_correct": true,
        "tab_bar_visible": true,
        "spacing_consistent": true,
        "safe_areas_respected": false,
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

#### IMPORTANT: Use XCUITest for Navigation, Not simctl

**`xcrun simctl` has NO tap/swipe/input commands.** Do NOT attempt to:
- Use `simctl io tap` (does not exist)
- Use AppleScript/osascript to click in the simulator window (unreliable coordinates)
- Use Chrome browser automation tools (those are for web pages, not native apps)
- Extract screenshots from `.xcresult` bundles (complex and brittle)

**The reliable approach: Write a `QAScreenshots` XCUITest class** that navigates
the app programmatically and saves screenshots directly to the filesystem.

#### Step 1: Write the QA Screenshot Test

Create `UITests/QAScreenshots.swift` — a dedicated test class that walks through
every screen and saves PNGs directly to disk:

```swift
import XCTest

final class QAScreenshots: XCTestCase {
    let app = XCUIApplication()
    // Use absolute path to project screenshots directory
    let screenshotDir = "<ABSOLUTE_PROJECT_PATH>/screenshots"

    override func setUp() {
        continueAfterFailure = true
        app.launch()
    }

    func testCaptureAllScreens() {
        // Create screenshots dir if needed
        try? FileManager.default.createDirectory(
            atPath: screenshotDir,
            withIntermediateDirectories: true
        )

        // 1. Home screen
        let someElement = app.buttons["someAccessibilityId"]
        XCTAssertTrue(someElement.waitForExistence(timeout: 10))
        saveScreenshot("qa-01-home")

        // 2. Navigate to next screen
        someElement.tap()
        XCTAssertTrue(app.otherElements["nextScreen"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1) // let animations settle
        saveScreenshot("qa-02-next-screen")

        // ... continue for each flow/screen
    }

    private func saveScreenshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let data = screenshot.pngRepresentation
        let url = URL(fileURLWithPath: "\(screenshotDir)/\(name).png")
        try? data.write(to: url)
    }
}
```

**Key patterns:**
- Use `accessibilityIdentifier` for element lookup (set these in your SwiftUI views)
- Use `waitForExistence(timeout:)` before interacting — never assume an element is there
- Add `Thread.sleep(forTimeInterval: 1)` after navigation for animations to settle
- Use `continueAfterFailure = true` so one screen failing doesn't skip the rest
- Save screenshots directly to filesystem — do NOT use `XCTAttachment` (extracting from xcresult is painful)

#### Step 2: Run the QA Screenshot Test

```bash
# Auto-detect simulator
SIM_DEST=$(bash scripts/find-simulator.sh)

# Run only the QA screenshot test
xcodebuild test -project {{PROJECT_NAME}}.xcodeproj -scheme {{PROJECT_NAME}} \
  -sdk iphonesimulator -destination "$SIM_DEST" \
  -only-testing '{{PROJECT_NAME}}UITests/QAScreenshots' \
  -resultBundlePath /tmp/qa-results.xcresult 2>&1 | tail -20
```

#### Step 3: Review Screenshots

Read each screenshot with the `Read` tool and apply the visual checklist (below).

#### Step 4: Dark Mode Pass

Dark mode cannot be toggled from inside XCUITest. Use `simctl` to switch appearance,
then relaunch and re-screenshot:

```bash
SIM_UUID=<simulator-uuid>

# Switch to dark mode
xcrun simctl ui $SIM_UUID appearance dark

# Relaunch the app
xcrun simctl terminate $SIM_UUID {{BUNDLE_ID}} 2>/dev/null
xcrun simctl launch $SIM_UUID {{BUNDLE_ID}}
sleep 3

# Screenshot
xcrun simctl io $SIM_UUID screenshot screenshots/qa-dark-home.png

# Restore light mode when done
xcrun simctl ui $SIM_UUID appearance light
```

**Common dark mode issue:** Text using `.secondary` or semantic colors becomes invisible
when the background uses a hardcoded light gradient. Fix: use `Color(.label)` /
`Color(.secondaryLabel)` and ensure background colors adapt, or use
`@Environment(\.colorScheme)` to pick gradient colors.

#### Step 5: Fix Issues and Re-verify

For EACH flow in `qa-report.json`:

1. Review screenshots against the visual checklist
2. **If an issue is found**:
   a. Record the issue in `steps[].issues`
   b. Fix the code
   c. Re-run the QA screenshot test (or just the affected portion)
   d. Re-review the new screenshot
   e. Continue only when the step passes
3. **After all steps pass**: mark `flow.verified = true`

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

**CRITICAL: Screenshot analysis must be meticulous.** Do not glance at a screenshot and
move on. Systematically scan from top to bottom, edge to edge. The most common QA failures
are subtle overlaps and clipping that pass a casual glance but are obvious to a real user.

### Layout & Structure
- [ ] Navigation title visible and not overlapping content
- [ ] Tab bar fully visible (not hidden behind content or other UI elements)
- [ ] No elements overlapping or clipped at screen edges
- [ ] Safe area respected (content not under notch/dynamic island/home indicator)
- [ ] Scroll views have correct content insets (content not hidden behind fixed bars)
- [ ] Bottom content not obscured by tab bar, toolbar, or floating buttons

### Overlap & Z-Order Analysis (CRITICAL — most missed category)

**Scan EVERY screenshot specifically for these overlap patterns:**

- [ ] **Tab bar vs content**: Full-width buttons, cards, or lists must NOT extend behind the
      tab bar. Check the bottom 80-100pt of the screen carefully — is any interactive element
      partially hidden behind the tab bar?
- [ ] **Floating buttons vs content**: FABs, "GO" buttons, or bottom-anchored CTAs must have
      clear separation from tab bars, toolbars, and bottom safe area. They must not overlap
      with the home indicator region on notched devices.
- [ ] **Overlapping text/badges**: Labels, badges, or status indicators must not overlap each
      other. Check areas where multiple indicators cluster (e.g., difficulty badge + score +
      operation indicator in the same row).
- [ ] **Stacked controls at screen bottom**: When a screen has BOTH a custom bottom bar/button
      AND a system tab bar, verify they don't fight for the same space. There must be clear
      visual separation between them.
- [ ] **Keyboard overlap**: When a text field or number pad is visible, verify it doesn't
      obscure the submit button, tab bar, or other interactive elements.
- [ ] **Scroll content behind fixed headers/footers**: Scroll the content to its extremes —
      does the first item peek out from under the nav bar? Does the last item sit above the
      tab bar with proper inset?

**How to catch overlaps:**
1. Look at every edge where two UI regions meet (nav bar/content, content/tab bar, content/keyboard)
2. Check if any element crosses a boundary it shouldn't
3. Pay special attention to the bottom 20% of the screen — this is where most overlaps occur
4. If a button or card touches or overlaps the tab bar, it is a FAIL even if it's "almost" okay

### Typography & Readability
- [ ] Text is not truncated (check long strings, especially in narrow containers)
- [ ] Font sizes are readable (minimum 11pt for body text)
- [ ] Text contrast meets accessibility standards (4.5:1 ratio)
- [ ] Labels aligned consistently
- [ ] Text does not overflow its container or overlap adjacent elements
- [ ] Dynamic type: text containers expand gracefully (no clipping at larger sizes)

### Interactive Elements
- [ ] Buttons are fully visible and have adequate tap targets (44x44pt minimum)
- [ ] Interactive elements have visual feedback states
- [ ] Form fields are not hidden behind keyboard
- [ ] Disabled states are visually distinct
- [ ] Tappable elements are not partially obscured by other views
- [ ] No two tappable elements overlap (would cause mis-taps)

### Spacing & Alignment
- [ ] Consistent margins and padding throughout the screen
- [ ] List items evenly spaced
- [ ] No unexpected gaps or cramped sections
- [ ] Content centered where appropriate
- [ ] Elements at screen edges have proper padding (not touching the edge)
- [ ] Vertical spacing between sections is consistent and intentional

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
- [ ] Gradient backgrounds don't wash out text in dark mode

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
| Full-width button overlaps tab bar | Ignoring safe area | Use `.padding(.bottom)` or `.safeAreaInset(edge: .bottom)` to push above tab bar |
| Floating CTA overlaps home indicator | Not respecting bottom safe area | Place button inside safe area or add `safeAreaPadding` |
| Two bottom bars stacked/overlapping | Custom bar + TabView conflict | Use `.toolbar` or `.safeAreaInset` instead of absolute positioning; let TabView manage its own bar |
| Badges/labels overlap each other | Fixed layout with dynamic content | Use `HStack` with `.layoutPriority`, or `ViewThatFits`, or reduce content at smaller sizes |
| Number pad covers submit button | Content doesn't account for input area | Wrap in `ScrollView`, use `.safeAreaInset`, or reposition button above input area |
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
