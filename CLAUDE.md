# {{PROJECT_NAME}} — iOS App Project

## CRITICAL: Loop Behavior

- NEVER stop and ask "should I continue?" — ALWAYS continue to the next feature
- NEVER ask for permission to proceed — the loop runs until ALL features pass
- After completing a feature: commit, update features.json, immediately start the next one
- Update `claude-progress.md` with summary, issues, next steps
- The stop gate hook will block you from stopping while features remain incomplete
- This is a LOOP — keep going until features.json has zero failing features
- **Parallelize aggressively** — use the dependency graph to spawn multiple feature-builder subagents in worktrees whenever possible

## Build & Test Commands

The project auto-detects its type: **SPM** (`Package.swift`) or **Xcode** (`.xcodeproj`).
All scripts (`init.sh`, `stop-gate.sh`, PostToolUse hooks) handle both. When adding new
scripts or hooks that build/test, you MUST support both project types — never hardcode
`swift build`/`swift test` without also handling `xcodebuild`.

### SPM project (Package.swift exists)
```bash
./init.sh                    # Bootstrap environment (idempotent)
swift build                  # Build the project
swift test                   # Run all unit tests
swift test --filter <Name>   # Run a specific test
```

### Xcode project (.xcodeproj exists)
```bash
./init.sh                    # Bootstrap environment (idempotent, auto-detects)
xcodebuild build -project <Name>.xcodeproj -scheme <Name> -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test  -project <Name>.xcodeproj -scheme <Name> -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16'
swiftlint lint               # Lint the codebase
```

## Template Submodule Files

This repo is used as a **git submodule** inside target projects. NEVER delete or modify these
template infrastructure files — they are part of the apploop template, not the target project:

- `CLAUDE.md`
- `init.sh`
- `stop-gate.sh`
- `scripts/` directory (e.g. `dependency-graph.py`)
- `docs/` directory (e.g. `architecture.md`, `conventions.md`, `parallel-development.md`, `qa-strategy.md`)
- `.claude/` configuration files (hooks, settings)

When the target project commits, these files must NOT be removed or flattened into the repo.
If git shows the `apploop` submodule as a tracked file/directory, leave it alone — do not
delete the submodule reference.

## Development Rules

- ALWAYS write the test BEFORE the implementation (TDD: red-green-refactor)
- NEVER mark a feature as passing in features.json without running the test AND verifying via computer use
- NEVER delete or modify existing tests unless explicitly told to
- Run `swift test` after every implementation change
- Run the full test suite before every commit
- Keep files under 300 lines — extract if larger

## Parallel Execution Strategy

See `docs/parallel-development.md` for the full guide.

### Dependency Graph

Every feature has a `depends_on` array in `features.json`. Use the dependency graph script
to determine which features can be built in parallel:

```bash
python3 scripts/dependency-graph.py --ready      # Next parallelizable batch
python3 scripts/dependency-graph.py --validate    # Check for cycles/missing deps
python3 scripts/dependency-graph.py               # All batches
```

### Orchestration Loop

1. Run `python3 scripts/dependency-graph.py --ready` to get the current batch
2. If batch has **2+ features in different layers/files** → spawn parallel subagents
3. If batch has **1 feature** or features **conflict** → build sequentially
4. For each parallel feature, use the `feature-builder` subagent:
   ```
   Use the feature-builder subagent to implement <feature-id>:
   <full feature spec from features.json>
   ```
5. Wait for all subagents to complete
6. Merge worktree branches back: `git merge worktree-<name> --no-ff`
7. Run `swift test` to verify integration
8. Update `features.json` with passing features
9. Repeat until all pass → enter QA mode

### When NOT to Parallelize

- Features that create/modify the **same files**
- Features where one creates a type/protocol the other consumes (add a `depends_on`)
- More than **3-4 simultaneous subagents** (diminishing returns, merge risk)
- When the project is freshly scaffolded (build the foundation sequentially first)

## UI Test Requirement (MANDATORY)

- **Every `ui-*` or `"category": "ui"` feature MUST have a corresponding XCUITest** in `UITests/`
- Unit tests alone are NOT sufficient for UI features — you MUST also write an XCUITest
- A `ui-*` feature is NOT done until it has BOTH:
  1. Unit tests for the ViewModel logic (`Tests/FeaturesTests/`)
  2. XCUITests that verify the UI behavior in the simulator (`UITests/`)
- XCUITests must exercise the actual `test_steps` from features.json
- NEVER mark a `ui-*` feature as passing without a green XCUITest covering it

### UI Test Execution Strategy

UI tests are expensive. **Never run the full suite when you can run targeted tests.**

#### Build Once, Test Many (Fastest Approach)

Separate build from test execution. Build the test bundle once, then run subsets instantly:

```bash
# Step 1: Build for testing (do this once per code change)
xcodebuild build-for-testing -project {{PROJECT_NAME}}.xcodeproj -scheme {{PROJECT_NAME}} \
  -sdk iphonesimulator -destination 'id={{SIMULATOR_UUID}}' \
  -derivedDataPath .build/derived

# Step 2: Run specific tests WITHOUT rebuilding (instant)
xcodebuild test-without-building -project {{PROJECT_NAME}}.xcodeproj -scheme {{PROJECT_NAME}} \
  -sdk iphonesimulator -destination 'id={{SIMULATOR_UUID}}' \
  -derivedDataPath .build/derived \
  -only-testing '{{PROJECT_NAME}}UITests/<TestClassName>'

# Run a single test method:
xcodebuild test-without-building -project {{PROJECT_NAME}}.xcodeproj -scheme {{PROJECT_NAME}} \
  -sdk iphonesimulator -destination 'id={{SIMULATOR_UUID}}' \
  -derivedDataPath .build/derived \
  -only-testing '{{PROJECT_NAME}}UITests/<TestClassName>/<testMethodName>'
```

#### When to Run What

| Trigger | What to run | Command |
|---------|------------|---------|
| Working on a feature | Only that feature's test class | `test-without-building -only-testing <Class>` |
| Feature complete, pre-commit | Feature class + classes sharing its views | `test-without-building -only-testing <Class1> -only-testing <Class2>` |
| Refactored shared views/navigation | Full UI suite | `test-without-building -only-testing {{PROJECT_NAME}}UITests` |
| Session startup (baseline) | Full UI suite | `test-without-building -only-testing {{PROJECT_NAME}}UITests` |
| QA phase final verification | Full UI suite | `test-without-building -only-testing {{PROJECT_NAME}}UITests` |

#### Skip Known-Good Tests

When one test class is failing and the rest are stable, use `-skip-testing` to exclude it temporarily while you fix:

```bash
# Run everything EXCEPT the broken class (to verify you didn't regress other features):
xcodebuild test-without-building -project {{PROJECT_NAME}}.xcodeproj -scheme {{PROJECT_NAME}} \
  -sdk iphonesimulator -destination 'id={{SIMULATOR_UUID}}' \
  -derivedDataPath .build/derived \
  -only-testing '{{PROJECT_NAME}}UITests' \
  -skip-testing '{{PROJECT_NAME}}UITests/<BrokenTestClass>'
```

#### Parallel Execution (When Suite Grows Large)

Enable parallel testing when the full suite exceeds ~2 minutes:

```bash
xcodebuild test-without-building -project {{PROJECT_NAME}}.xcodeproj -scheme {{PROJECT_NAME}} \
  -sdk iphonesimulator -destination 'id={{SIMULATOR_UUID}}' \
  -derivedDataPath .build/derived \
  -only-testing '{{PROJECT_NAME}}UITests' \
  -parallel-testing-enabled YES
```

**Requirement for parallel tests**: Each test class must be fully independent — no shared
state between classes, no ordering dependencies. Use `launch()` in every `setUp()`.

#### Speed Tips for Writing XCUITests

- **Use `accessibilityIdentifier`** for element lookup — faster than label/predicate queries
- **Use `app.launchArguments`** to skip onboarding, pre-seed test data, disable animations:
  ```swift
  override func setUp() {
      app.launchArguments += ["--uitesting", "--skip-onboarding"]
      app.launch()
  }
  ```
- **Avoid `waitForExistence` with long timeouts** — use short timeouts (2-3s) or polling loops
- **Don't requery elements** — store element references and reuse them
- **Minimize navigation** — launch directly to the screen under test via launch arguments when possible

### UI Test Class -> Feature Mapping

Keep this table updated. The stop gate and QA mode use it to determine which tests to run.

| Test Class | Features |
|---|---|
| `ExampleUITests` | ui-001, ui-002 |

## Loop States

The development loop has 3 states, enforced by the stop gate:

1. **Features Failing** — implement features using TDD until all pass
2. **QA Mode** — all features pass → visual polish & user flow verification (see below)
3. **Improvement Mode** — QA verified → research and add new features

The stop gate blocks you from stopping in ALL states. You transition automatically.

## QA Protocol (MANDATORY)

QA mode activates after all features pass. See `docs/qa-strategy.md` for the full guide.

**Screenshots are MANDATORY at every QA step. Never skip a screenshot.**

### QA Workflow Summary

1. **Generate** `qa-report.json` from `features.json` (group features into user flows)
2. **For each flow**: build → launch → perform actions → screenshot every step → verify visually
3. **Visual checklist** (apply to every screenshot):
   - No overlapping elements, text not truncated
   - Buttons fully visible with adequate tap targets
   - Navigation title and tab bar correct
   - Spacing consistent, safe areas respected
   - Dark mode pass for all screens
4. **If issue found**: fix code → rebuild → re-screenshot → re-verify
5. **Mark flow verified** in `qa-report.json` when all steps + checklist pass
6. **Soak test (MANDATORY)**: Use the app like a real user — don't just tap once per screen:
   - Create many items (5-10+), navigate back and forth, repeat actions multiple times
   - Let state accumulate: lists should scroll, badges/counters should reach real numbers
   - Perform create/delete cycles, toggle settings on/off, interrupt mid-flow by switching tabs
   - Screenshot at state milestones (after many items, after delete cycles, after returning to screens)
   - Look for: stale data, badge drift, layout breaking with many items, ghost items, lost scroll position
7. **After all flows verified (including soak)**: run full XCUITest suite, set `qa-report.json` status to `"passed"`, commit

### QA Screenshot Strategy (CRITICAL)

**DO NOT** attempt to interact with the simulator via `simctl tap` (doesn't exist),
AppleScript coordinate clicking (unreliable), or Chrome browser tools (web only).

**DO** write a `QAScreenshots` XCUITest class that navigates the app and saves
screenshots directly to the filesystem. This is the only reliable approach.

```swift
// UITests/QAScreenshots.swift — saves PNGs directly to disk
private func saveScreenshot(_ name: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let data = screenshot.pngRepresentation
    let url = URL(fileURLWithPath: "\(screenshotDir)/\(name).png")
    try? data.write(to: url)
}
```

Run it with: `xcodebuild test -only-testing '{{PROJECT_NAME}}UITests/QAScreenshots'`

For dark mode, use `simctl` outside the test:
```bash
xcrun simctl ui {{SIMULATOR_UUID}} appearance dark
xcrun simctl terminate {{SIMULATOR_UUID}} {{BUNDLE_ID}}
xcrun simctl launch {{SIMULATOR_UUID}} {{BUNDLE_ID}}
sleep 3
xcrun simctl io {{SIMULATOR_UUID}} screenshot screenshots/qa-dark-home.png
xcrun simctl ui {{SIMULATOR_UUID}} appearance light
```

See `docs/qa-strategy.md` for the full QA screenshot workflow.

### QA Report Status

- `qa-report.json` absent or `status: "in_progress"` → QA Mode active
- `qa-report.json` with `status: "passed"` → QA complete, enter Improvement Mode
- When new features are added in Improvement Mode, delete `qa-report.json` so QA re-runs

## Session Protocol

### Startup
1. Read `claude-progress.md` for prior session context
2. Read `git log --oneline -20` for recent commits
3. Read `features.json` — identify next incomplete feature
4. Check `qa-report.json` — determine current loop state
5. Run `./init.sh` to ensure environment is ready
6. Run `swift test` to verify baseline is green
7. Fix any broken tests before starting new work

### Shutdown
1. Run full test suite — all must pass
2. Commit all changes with descriptive messages
3. Update `claude-progress.md` with summary, issues, next steps
4. Update `features.json` if any features now pass
5. Update `qa-report.json` if QA work was done

## Architecture

See `docs/architecture.md` for full details.

```
Domain (Models, Protocols)     -> zero dependencies
Services (Business Logic)      -> depends on Domain only
Features (ViewModels + Views)  -> depends on Domain + Services
App (Composition Root)         -> wires everything together
```

- Use `@Observable` macro, not `ObservableObject`
- Use Swift Testing (`@Test`, `#expect`), not XCTest
- Use structured concurrency (`async/await`, actors), not GCD
- Use SwiftData for persistence
- Use `NavigationStack` with typed paths

## Conventions

See `docs/conventions.md` for full details.

- Swift API Design Guidelines for naming
- `@MainActor` on all UI-bound types
- `Sendable` conformance for cross-isolation types
- Value types by default, reference types only when identity matters
- `private` by default, `internal` when needed, `public` for API surface
- Structured logging via `os.Logger` — never `print()`
- No force unwraps except in tests and previews
- Accessibility labels on all interactive elements

## Feature Tracking

- Feature specs live in `features.json` (JSON, not Markdown)
- Only modify the `passes` field — never delete or edit specs
- Each feature has explicit `test_steps` for verification
- Each feature has a `depends_on` array of feature IDs it requires
- Optional `files` array lists key files for conflict detection
- Run `python3 scripts/dependency-graph.py --validate` after editing features.json

## Verification

After implementing a feature, verify with computer use:
1. Build and run the app
2. Navigate to the relevant screen
3. Perform the user action described in test_steps
4. Capture screenshot evidence
5. If broken, fix and re-verify before marking as passing

**For `ui-*` or `"category": "ui"` features specifically:**
1. Write XCUITest FIRST (red)
2. Implement the UI (green)
3. Run XCUITests in simulator — must pass
4. Capture screenshot evidence, analyze to see if there is any overlapping or things off
5. Only THEN mark as passing in features.json
