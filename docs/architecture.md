# Architecture

## Layer Dependency Rules

```
Domain (Models, Protocols)     -> zero dependencies
         ^
Services (Business Logic)      -> depends on Domain only
         ^
Features (ViewModels + Views)  -> depends on Domain + Services
         ^
App (Composition Root)         -> wires everything together
```

**These rules are enforced mechanically** by `scripts/check-architecture.sh` and CI.

### Domain Layer
- Pure Swift types: models, protocols, enums, errors
- No imports of Services, Features, or App
- No UIKit/SwiftUI imports
- Fully testable in isolation

### Services Layer
- Business logic, networking, persistence
- Depends only on Domain protocols and types
- Uses `async/await` and actors for concurrency
- Injected via protocols — never instantiated directly in Features

### Features Layer
- One directory per feature (e.g., `Features/Auth/`, `Features/Home/`)
- Contains `@Observable` view models and SwiftUI views
- Views are small and composable (<40 lines body preferred)
- Depends on Domain types and Service protocols
- Never imports another Feature directly — cross-feature communication goes through Services or App

### App Layer
- Composition root: creates services, injects into features
- Navigation coordination
- App-level configuration (appearance, permissions)

## Data Flow

```
User Action -> View -> ViewModel (@Observable) -> Service -> Domain
                ^                                    |
                +------------ state update ----------+
```

- Data flows down through initializers and `@Environment`
- State changes propagate automatically via `@Observable`
- No Combine — use `AsyncSequence` for reactive streams

## Navigation

- `NavigationStack` with `NavigationPath` stored in a router
- Router is an `@Observable` object at the App level
- Features declare their `navigationDestination(for:)` handlers
- Deep links resolved through the router

## Persistence

- SwiftData with `@Model` types defined in Domain
- `@Query` in views for automatic fetching
- `VersionedSchema` + `SchemaMigrationPlan` for migrations

## Networking

- Single `APIClient` actor in Services layer
- Uses `URLSession` with `async/await`
- `Codable` response types in Domain
- Retry and cancellation via structured concurrency
