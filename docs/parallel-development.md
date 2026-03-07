# Parallel Development — Multi-Agent Feature Building

## Overview

The apploop development loop supports **parallel feature implementation** using Claude Code's
subagent system with git worktree isolation. Instead of building features one at a time, the
orchestrator (main agent) analyzes the dependency graph and spawns multiple `feature-builder`
subagents that work simultaneously in isolated worktrees.

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│                    ORCHESTRATOR (main agent)             │
│                                                         │
│  1. Read features.json                                  │
│  2. Run dependency-graph.py --ready                     │
│  3. Identify parallel batch (features with deps met)    │
│  4. Check for file/layer conflicts                      │
│  5. Spawn feature-builder subagents (isolation: worktree) │
│  6. Wait for all to complete                            │
│  7. Merge branches back to main                         │
│  8. Run full test suite (integration check)             │
│  9. Update features.json                                │
│  10. Loop until all features pass → QA mode             │
└─────────────────────────────────────────────────────────┘
        │               │               │
        ▼               ▼               ▼
   ┌─────────┐    ┌─────────┐    ┌─────────┐
   │ worktree │    │ worktree │    │ worktree │
   │ core-001 │    │ core-002 │    │ core-003 │
   │          │    │          │    │          │
   │ TDD loop │    │ TDD loop │    │ TDD loop │
   │ commit   │    │ commit   │    │ commit   │
   └─────────┘    └─────────┘    └─────────┘
```

## Feature Dependencies (`depends_on`)

Every feature in `features.json` has a `depends_on` array listing feature IDs that must
pass before this feature can be started.

```json
{
  "id": "ui-001",
  "description": "User login screen",
  "depends_on": ["core-001", "service-001"],
  "phase": "mvp",
  "category": "ui",
  "passes": false,
  "test_steps": ["..."]
}
```

### Dependency Rules

- **Empty `depends_on`**: Feature has no dependencies — can start immediately
- **All deps passing**: Feature is "ready" — can be built now
- **Some deps failing**: Feature is "blocked" — must wait
- **No cycles allowed**: The dependency graph must be a DAG (directed acyclic graph)

### Designing Good Dependencies

When writing `features.json`, think about what each feature actually needs:

| Feature Type | Typical Dependencies |
|-------------|---------------------|
| Domain models | None (foundation layer) |
| Service logic | Domain models it uses |
| UI ViewModel | Service it calls, domain models it displays |
| UI View | Its ViewModel feature |
| Integration/glue | The features it wires together |

**Tips:**
- Keep the graph as flat as possible — deep chains serialize everything
- Domain and service features should rarely depend on each other (they work on different layers)
- UI features typically depend on their backing service/model features
- Group related work into one feature rather than creating unnecessary chains

## Dependency Graph Script

The `scripts/dependency-graph.py` script analyzes `features.json` and outputs work batches:

```bash
# Show all batches (topological sort)
python3 scripts/dependency-graph.py

# Show only the next batch of ready-to-build features
python3 scripts/dependency-graph.py --ready

# Validate the graph (check for cycles, missing deps)
python3 scripts/dependency-graph.py --validate

# Output Graphviz DOT format (for visualization)
python3 scripts/dependency-graph.py --dot | dot -Tpng -o dep-graph.png
```

### Output Format

```
BATCH=1
FEATURE=core-001|mvp|User model and validation|domain
FEATURE=core-002|mvp|Authentication protocol|domain
BATCH=2
FEATURE=service-001|mvp|Auth service implementation|services
FEATURE=service-002|mvp|User storage service|services
BATCH=3
FEATURE=ui-001|mvp|Login screen|features
FEATURE=ui-002|mvp|Registration screen|features
```

Features within the same batch can be built in parallel. Batches must be executed in order.

## Orchestration Protocol

### When to Parallelize

Use parallel subagents when:
- The ready batch has **2+ features**
- Features are in **different architecture layers** (domain, services, features)
- Features touch **different files** (no shared dependencies being created)

Use sequential (single agent) when:
- Only 1 feature is ready
- Features modify the **same files** (shared models, shared views)
- Features are tightly coupled (one creates an API the other consumes)

### Recommended Limits

- **Max 3-4 parallel subagents** — beyond this, merge conflicts increase and coordination
  overhead outweighs the speed benefit
- **Max 5-6 features per subagent** if batching multiple small features per agent
- Keep subagents focused on **one architecture layer** when possible

### Step-by-Step Orchestration

1. **Analyze the graph**:
   ```
   python3 scripts/dependency-graph.py --ready
   ```

2. **Check for conflicts**: Features in the same batch might still conflict if they:
   - Add to the same file (e.g., both add cases to an enum)
   - Create types with the same name
   - Modify shared navigation or app composition

   If conflicts are likely, run those features sequentially.

3. **Spawn subagents** with worktree isolation:
   ```
   Use the feature-builder subagent in a worktree to implement <feature-id>:
   <paste full feature spec from features.json>
   ```

   For multiple features in parallel, spawn them all in one message:
   ```
   Implement these features in parallel using feature-builder subagents in worktrees:
   1. core-001: <spec>
   2. core-002: <spec>
   3. core-003: <spec>
   ```

4. **Wait for all subagents** to complete. Each commits to its own branch.

5. **Merge branches** back to main:
   ```bash
   git merge worktree-<feature-id> --no-ff -m "Merge <feature-id>"
   ```
   If merge conflicts occur, resolve them manually.

6. **Run full test suite** to verify integration:
   ```bash
   swift test
   ```

7. **Update features.json** — mark passing features.

8. **Repeat** with the next batch.

## Conflict Prevention

### Architecture-Based Isolation

The 4-layer architecture naturally isolates work:

```
Domain     → Each model/protocol is its own file
Services   → Each service is its own file
Features   → Each feature has its own directory
App        → Composition root (single point of integration)
```

**Safe to parallelize:** Features in different layers, or in different feature directories.
**Risky to parallelize:** Features that both add to the App composition root, or both extend
the same domain model.

### File Ownership Convention

When defining features, note which files they'll create/modify. If two features share
files, they should have a dependency relationship (or be built sequentially).

## Worktree Lifecycle

1. **Created**: When a feature-builder subagent starts, Claude creates a worktree at
   `.claude/worktrees/<name>/` branching from the current HEAD.

2. **Active**: The subagent works in its isolated directory. Changes don't affect
   the main working tree.

3. **Completed**: The subagent commits its work and returns results to the orchestrator.

4. **Merged**: The orchestrator merges the branch back to main.

5. **Cleaned up**: Worktrees are automatically cleaned up after the subagent finishes.
   If changes exist, the branch is preserved for merging.

### Manual Worktree Management

```bash
# List all worktrees
git worktree list

# Remove a specific worktree
git worktree remove .claude/worktrees/<name>

# Prune stale worktree references
git worktree prune
```

## Integration with the Stop Gate

The stop gate reads `features.json` and understands the dependency graph:

1. **Features Failing** → Shows the next ready batch, not just the next single feature
2. **QA Mode** → All features pass, dependency graph fully resolved
3. **Improvement Mode** → QA verified

The stop gate prompt includes context about whether parallel execution is possible for
the current batch.

## Example: Full Parallel Session

```
Session starts:
  → Read features.json: 10 features, 0 passing
  → Run dependency-graph.py --ready: Batch 1 has 3 features (all domain layer)
  → Spawn 3 feature-builder subagents in worktrees
  → All 3 complete (~3 min each, running simultaneously)
  → Merge all 3 branches
  → Run swift test → all pass
  → Update features.json: 3/10 passing

  → Run dependency-graph.py --ready: Batch 2 has 2 features (services layer)
  → Spawn 2 feature-builder subagents
  → Both complete
  → Merge, test, update: 5/10 passing

  → Continue until 10/10 passing
  → Enter QA mode
  → QA verified → Improvement mode
```

## Troubleshooting

| Problem | Cause | Solution |
|---------|-------|---------|
| Merge conflict after subagent | Two features modified same file | Run them sequentially, or resolve conflict manually |
| Tests pass in worktree but fail after merge | Integration issue between features | Fix in main, re-run tests |
| Subagent can't find dependencies | Feature depends on uncommitted work | Ensure deps are committed and merged before spawning |
| Worktree not cleaned up | Subagent crashed or was interrupted | `git worktree remove .claude/worktrees/<name>` |
| Cycle detected in dependency graph | Circular `depends_on` references | Fix features.json to break the cycle |
