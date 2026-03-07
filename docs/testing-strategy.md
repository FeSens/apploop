# Testing Strategy

## TDD Workflow

Every feature follows red-green-refactor:

1. **Red**: Write a failing test that describes the desired behavior
2. **Green**: Write the minimum implementation to make the test pass
3. **Refactor**: Clean up while keeping tests green
4. **Verify**: Use computer use to confirm the feature works end-to-end

## Test Layers

### Unit Tests (Swift Testing)
- **Scope**: Single type in isolation
- **Speed**: <5 seconds total
- **When**: After every edit
- **Location**: `Tests/<Feature>Tests/`
- **What to test**:
  - ViewModel logic and state transitions
  - Service business rules
  - Domain model validation
  - Error handling paths

```swift
@Test("User authentication succeeds with valid credentials")
func authenticateWithValidCredentials() async throws {
    let service = AuthService(client: MockAPIClient())
    let result = try await service.authenticate(email: "test@example.com", password: "valid")
    #expect(result.isAuthenticated)
}
```

### Integration Tests (Swift Testing)
- **Scope**: Multiple types working together
- **Speed**: <30 seconds total
- **When**: After feature implementation complete
- **What to test**:
  - ViewModel + Service interaction
  - SwiftData persistence roundtrips
  - Navigation flows

### XCUITest (UI Integration Tests)
- **Scope**: Full app running in simulator via XCTest
- **Speed**: ~5 seconds per test
- **When**: After UI feature implementation
- **What to test**:
  - Element existence and tappability
  - State transitions (submit -> feedback -> next)
  - Tab navigation and screen switching
- **Key principle**: Keep UI tests thin — only test what you can't test at the unit/integration level. Push logic into ViewModels and test there (fast). UI tests should verify wiring and layout, not business rules.

### E2E Screenshot Verification (Simulator)
- **Scope**: Full app visual verification via `xcrun simctl`
- **Speed**: <2 minutes per flow
- **When**: Before marking a UI feature as passing AND during QA phase
- **What to test**:
  - Layout correctness (no overlaps, no clipped buttons)
  - Typography and spacing
  - Navigation title placement
  - Tab bar visibility
  - Timer/animation state

### QA Phase (Post-Feature Verification)
- **Scope**: Full app user flow simulation with mandatory screenshots
- **Speed**: 5-15 minutes for complete QA pass
- **When**: After ALL features pass — triggered automatically by stop gate
- **What to test**:
  - Complete user flows end-to-end (grouped from features.json)
  - Dark mode on all screens
  - Landscape orientation on key screens
  - Visual checklist: overlaps, truncation, tap targets, spacing, contrast
- **Output**: `qa-report.json` with screenshot evidence for every step
- **See**: `docs/qa-strategy.md` for full protocol

### Verification Protocol

```
1. Build: xcodebuild -scheme App -sdk iphonesimulator -destination 'id=UUID' build
2. Install: xcrun simctl install UUID path/to/App.app
3. Launch: xcrun simctl launch UUID com.bundle.id
4. Wait: sleep 2
5. Screenshot: xcrun simctl io UUID screenshot /tmp/state.png
6. Visually verify against checklist (nav title, tab bar, buttons, spacing)
7. Run XCUITests: xcodebuild test -only-testing:UITests
8. If ALL PASS: update features.json, commit
9. If FAIL: fix the issue, return to step 1
```

## Test Naming

Use descriptive names that explain the scenario:

```swift
@Test("Login button is disabled when email field is empty")
@Test("Error message appears after three failed login attempts")
@Test("User is redirected to home after successful registration")
```

## Mocking Strategy

- Define protocols in Domain layer for all services
- Create mock implementations in test targets
- Use closures for simple one-off mocks:

```swift
struct MockAuthService: Authenticating {
    var authenticateResult: Result<User, AuthError> = .success(.stub)

    func authenticate(email: String, password: String) async throws(AuthError) -> User {
        try authenticateResult.get()
    }
}
```

## XCUITest Execution Optimization

UI tests are the slowest layer. Use these strategies to keep the feedback loop fast:

### Build Once, Test Many

Separate the build step from test execution. This avoids recompiling when running different
test subsets:

```bash
# Build the test bundle once:
xcodebuild build-for-testing -scheme {{PROJECT_NAME}} -sdk iphonesimulator \
  -destination 'id={{SIMULATOR_UUID}}' -derivedDataPath .build/derived

# Run subsets instantly (no rebuild):
xcodebuild test-without-building -scheme {{PROJECT_NAME}} -sdk iphonesimulator \
  -destination 'id={{SIMULATOR_UUID}}' -derivedDataPath .build/derived \
  -only-testing '{{PROJECT_NAME}}UITests/LoginUITests'
```

### Selective Execution

Always run the minimum set of tests needed:

- **`-only-testing`**: Run specific classes or methods. Accepts `TestTarget/TestClass/TestMethod`.
  Multiple `-only-testing` flags can be combined in one command.
- **`-skip-testing`**: Exclude specific tests from a broader run. Useful for skipping a known-broken
  test while verifying no regressions elsewhere.
- **Feature mapping**: Use the "UI Test Class -> Feature Mapping" table in CLAUDE.md to know
  which test classes cover which features. Run only what's relevant.

### Parallel Execution

When the suite grows beyond ~2 minutes, enable parallelism:

```bash
xcodebuild test-without-building ... -parallel-testing-enabled YES
```

**Requirements for parallel safety:**
- Each test class must be fully independent (no shared state, no ordering)
- Every test must call `app.launch()` in `setUp()`
- No shared files, databases, or user defaults between classes
- Use unique `accessibilityIdentifier` values (no collisions between features)

### Writing Fast XCUITests

1. **Use `accessibilityIdentifier`** everywhere — it's the fastest lookup method
2. **Use `app.launchArguments`** to bypass setup flows:
   ```swift
   app.launchArguments += ["--uitesting", "--skip-onboarding", "--seed-test-data"]
   ```
   Handle these in the app's launch:
   ```swift
   if CommandLine.arguments.contains("--skip-onboarding") {
       // Skip to main screen
   }
   ```
3. **Minimize navigation depth** — launch directly to the screen under test
4. **Short timeouts** — use `waitForExistence(timeout: 2)` not `timeout: 10`
5. **Cache element references** — don't re-query `app.buttons["id"]` in a loop
6. **Avoid sleep()** — use `waitForExistence` or expectation-based waits instead
7. **Test one thing per test method** — faster to re-run, easier to diagnose failures
8. **Disable animations in test mode**:
   ```swift
   // In app delegate or scene delegate:
   if CommandLine.arguments.contains("--uitesting") {
       UIView.setAnimationsEnabled(false)
   }
   ```

### When to Run the Full Suite

Only run ALL UI tests at these checkpoints (not after every change):

- Session startup (baseline check)
- Before committing (final verification)
- After refactoring shared views, navigation, or app-level code
- QA phase final verification
- Before marking the last feature as passing

During development, **always use targeted execution** with `-only-testing`.

## What NOT to Test

- SwiftUI view layout (use previews instead)
- Apple framework behavior
- Trivial getters/setters
- Private implementation details
