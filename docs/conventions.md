# Conventions

## Naming

Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/):
- Clarity at the point of use
- Prefer method names that read as grammatical English phrases
- Name types and protocols with nouns (e.g., `User`, `AuthService`, `Authenticating`)
- Name methods with verbs (e.g., `authenticate()`, `fetchUsers()`)
- Boolean properties read as assertions: `isValid`, `hasContent`, `canSubmit`

## File Organization

- One primary type per file
- File name matches the primary type name
- Group by feature, not by layer:
  ```
  Features/
    Auth/
      AuthViewModel.swift
      LoginView.swift
      SignUpView.swift
    Home/
      HomeViewModel.swift
      HomeView.swift
  ```

## Access Control

- `private` by default
- `internal` when needed within the module
- `public` only for API surface of shared packages
- Use `final` on classes not designed for subclassing

## Concurrency

- `@MainActor` on all UI-bound types (views, view models)
- `actor` for shared mutable state
- `async let` and `TaskGroup` for parallel work
- `Task {}` only from synchronous contexts
- Check `Task.isCancelled` in long-running work
- Never use `DispatchQueue` — use Swift concurrency

## Error Handling

- Typed throws (`throws(MyError)`) for domain-specific errors
- Domain error types per feature (e.g., `AuthError`, `NetworkError`)
- `Result` only at API boundaries
- Never catch-and-ignore — always handle or propagate

## Logging

- Use `os.Logger` with subsystem and category
- Never use `print()` — it's invisible in production
- Log at appropriate levels: `.debug`, `.info`, `.error`, `.fault`
- Include context: `logger.error("Failed to fetch user \(userID)")`

## SwiftUI

- View body under 40 lines — extract subviews
- `@State` for view-local state
- `@Environment` for dependency injection
- `@Bindable` for bindings to `@Observable` objects
- No `@StateObject` or `@ObservedObject` — use `@Observable` macro
- `#Preview` for every view, covering multiple states

## Testing

- Use Swift Testing framework (`@Test`, `#expect`)
- Test file naming: `<Type>Tests.swift`
- One test suite per type being tested
- Use `@Test("descriptive name")` for clarity
- Parameterized tests via `@Test` arguments
- Mock via protocols or closures — no mocking frameworks
- No network or filesystem in unit tests
