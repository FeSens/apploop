# SwiftUI Testing Best Practices for iOS Apps

## Overview

Practical best practices for testing SwiftUI iOS apps. Covers unit testing with Swift Testing, UI testing with XCUITest, and screenshot-based visual verification via simulator automation.

---

## 1. Test Architecture: The Three Layers

### Layer 1: Unit Tests (Swift Testing)

Fast, isolated tests for ViewModels, Services, and Domain logic.

```swift
import Testing
@testable import Features
@testable import Domain

@Suite("PracticeViewModel")
struct PracticeViewModelTests {

    @Test("Submitting correct answer sets state to correct")
    @MainActor
    func submitCorrect() {
        let vm = MyViewModel(dependency: MockDependency())
        vm.performAction()
        #expect(vm.state == .success)
    }
}
```

**Key rules:**
- Use `@MainActor` on tests that touch `@Observable` ViewModels (Swift 6 concurrency requirement)
- Inject dependencies via protocols — never test against real services in unit tests
- Use fixed/stub implementations to control test inputs
- Keep tests under 5 seconds total

### Layer 2: XCUITest (UI Integration Tests)

Test real app behavior in the simulator.

```swift
import XCTest

@MainActor
final class MainFlowUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }

    func testMainScreenElements() {
        XCTAssertTrue(app.buttons["primaryAction"].exists)
        XCTAssertTrue(app.staticTexts["welcomeTitle"].exists)
    }
}
```

### Layer 3: Screenshot Verification (Simulator Automation)

Visual confirmation that layout, typography, and spacing are correct.

```bash
xcodebuild -project App.xcodeproj -scheme App -sdk iphonesimulator \
  -destination 'id=DEVICE_UUID' build
xcrun simctl install DEVICE_UUID path/to/App.app
xcrun simctl launch DEVICE_UUID com.bundle.id
sleep 2
xcrun simctl io DEVICE_UUID screenshot /tmp/screenshot.png
```

---

## 2. XCUITest Patterns and Pitfalls

### 2.1 Element Identification

Use `accessibilityIdentifier` for elements that need to be found programmatically:

```swift
// In SwiftUI view:
Button("Action") { ... }
    .accessibilityIdentifier("actionButton")

// In XCUITest:
let button = app.buttons["actionButton"]
XCTAssertTrue(button.exists)
```

### 2.2 Waiting for Elements: Avoid `waitForExistence` Traps

`waitForExistence(timeout:)` blocks for the full timeout if the element never appears. Use polling loops for OR conditions:

```swift
let success = app.staticTexts["Success"]
let error = app.staticTexts["Error"]
let deadline = Date().addingTimeInterval(3)
var found = false
while Date() < deadline {
    if success.exists || error.exists {
        found = true
        break
    }
    Thread.sleep(forTimeInterval: 0.1)
}
XCTAssertTrue(found, "Feedback should appear after submission")
```

### 2.3 Swift 6 Concurrency in XCUITests

`XCUIApplication()` is main-actor-isolated in Swift 6. Mark your test class with `@MainActor`:

```swift
@MainActor
final class MyUITests: XCTestCase {
    let app = XCUIApplication()
}
```

### 2.4 Testing Dynamic Content

When displayed content is randomized, test for structural properties:

```swift
func testContentIsDisplayed() {
    let hasContent = app.staticTexts.allElementsBoundByIndex.contains { text in
        !text.label.isEmpty
    }
    XCTAssertTrue(hasContent, "Some content should be displayed")
}
```

---

## 3. Screenshot-Based Visual Verification

### Screenshot Checklist

| Check | What to look for |
|-------|-----------------|
| Navigation title | Not overlapping content, correct display mode |
| Tab bar | Fully visible, not overlapping bottom content |
| Interactive elements | Buttons fully visible and not clipped |
| Text content | Not truncated, readable font size |
| Spacing | Consistent margins, no overlapping elements |

### Common Layout Issues and Fixes

**Navigation title overlaps content:**
```swift
#if os(iOS)
.navigationBarTitleDisplayMode(.inline)
#endif
```

**Button hidden behind tab bar:**
```swift
VStack(spacing: 0) {
    contentArea.frame(maxHeight: .infinity)
    bottomControls.padding(.bottom, 8)
}
```

---

## 4. Platform Compatibility (iOS + macOS)

### iOS-Only APIs
```swift
.navigationTitle("Screen")
#if os(iOS)
.navigationBarTitleDisplayMode(.inline)
#endif
```

### UIKit Colors
```swift
// Instead of: Color(UIColor.systemGray5)
Color.gray.opacity(0.1)  // Works on all platforms
```

### ShapeStyle vs Color
```swift
// Wrong:  .foregroundStyle(.accentColor)
// Correct:
.foregroundStyle(Color.accentColor)
```

---

## 5. SwiftUI Compiler Pitfalls

### "Unable to Type-Check This Expression"

Complex `ForEach` bodies cause the Swift compiler to time out. Break into extracted methods:

```swift
// Good — extracted method:
ForEach(items) { item in
    itemRow(item: item)
}

private func itemRow(item: Item) -> some View {
    HStack { ... }
}
```

---

## 6. Testing Observable ViewModels

### @Observable + @MainActor

All `@Observable` ViewModels should be `@MainActor`. Tests must also be `@MainActor`:

```swift
@Test("State transitions correctly")
@MainActor
func stateTransition() {
    let vm = MyViewModel(dependency: mockDep)
    vm.performAction()
    #expect(vm.state == .expected)
}
```

### Injecting Dependencies

Use protocol-based injection:

```swift
// Protocol in Domain:
public protocol DataProviding: Sendable {
    func fetch() async -> [Item]
}

// ViewModel accepts protocol:
public init(provider: DataProviding = RealProvider()) {
    self.provider = provider
}
```

---

## 7. XCUITest Performance

### Launch Arguments for Speed

Configure the app to skip unnecessary setup during UI testing:

```swift
// In XCUITest setUp():
override func setUp() {
    continueAfterFailure = false
    app.launchArguments += ["--uitesting", "--skip-onboarding", "--disable-animations"]
    app.launch()
}

// In app code (AppDelegate or @main struct):
if CommandLine.arguments.contains("--uitesting") {
    UIView.setAnimationsEnabled(false)
}
if CommandLine.arguments.contains("--skip-onboarding") {
    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
}
```

### Element Lookup Performance

`accessibilityIdentifier` is the fastest way to find elements. Avoid chained queries:

```swift
// Fast — direct identifier lookup:
app.buttons["submitButton"].tap()

// Slow — traversal-based query:
app.scrollViews.otherElements.buttons.matching(identifier: "submitButton").firstMatch.tap()
```

### Parallel-Safe Test Design

For tests to run in parallel, each class must be fully isolated:

```swift
@MainActor
final class SettingsUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        // Each class launches its own app instance
        app.launchArguments += ["--uitesting", "--reset-state"]
        app.launch()
    }

    // No class-level shared state
    // No dependency on test execution order
    // No shared files or databases
}
```

## 8. Lessons Learned

1. **Always take screenshots after UI changes** — automated tests can pass while the UI is broken
2. **`waitForExistence` is a trap for OR conditions** — use polling loops instead
3. **Test structural properties of dynamic content** — don't assert on random values
4. **Break up complex SwiftUI expressions** — the compiler has a strict type-checking timeout
5. **iOS-only APIs break SPM macOS builds** — always wrap in `#if os(iOS)`
6. **`@MainActor` is required everywhere in Swift 6** — test classes, ViewModel tests, and any code touching `@Observable` types
7. **Verify interactive element placement** — the most common layout bug is buttons hidden behind the tab bar
