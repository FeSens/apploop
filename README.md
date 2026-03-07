# AppLoop — Autonomous Claude Code Development Loop

A boilerplate for running Claude Code in an autonomous TDD development loop that builds iOS apps feature-by-feature. Features are parallelized across worktree-isolated subagents, then verified through a mandatory screenshot-driven QA phase.

## One Prompt. Full App.

```
> Create an iOS app that teaches kids mental math. It should have timed
> challenges, difficulty levels, a progress tracker with streaks, and fun
> animations when they get answers right. Make it feel like a game.
```

That's it. Drop this prompt into Claude Code with AppLoop configured, and walk away.

**What happens next:**

1. Claude scaffolds the Xcode project, defines 30+ features in `features.json` with a full dependency graph, and starts the loop
2. Domain models and protocols are built first (no dependencies), 3-4 at a time in parallel worktrees
3. Services layer follows — auth, scoring, streak tracking — each in its own worktree
4. UI screens come last — timed challenge view, difficulty picker, progress dashboard — all with XCUITests
5. Every feature: test written first, implementation second, screenshot verification third
6. When all features pass, QA mode kicks in — Claude uses the app like a real kid would: tapping fast, getting answers wrong on purpose, building up streaks, switching between screens, checking that badges update and animations fire
7. Issues found? Fixed automatically, re-screenshotted, re-verified
8. QA passes? Claude researches what the best math apps do, adds 5 new polish features, and loops again

**What you get:**

- A working app with 30+ features, 100+ unit tests, and full UI test coverage
- A `screenshots/` folder with visual evidence of every QA check
- A `qa-report.json` proving every flow was verified
- Git history with one clean commit per feature

**What you do:** Watch. Or go get coffee. The stop gate won't let Claude quit until YOU SAY the app is done (press esc to stop). This can run for hours, days or even weeks.

---

## What This Is

This template sets up Claude Code to:
1. Read a `features.json` spec file with all planned features and their dependency graph
2. Analyze dependencies and spawn parallel `feature-builder` subagents in git worktrees
3. Each subagent implements its feature using TDD (red-green-refactor) in isolation
4. The orchestrator merges branches, runs integration tests, and loops
5. After all features pass, enter a QA phase with mandatory screenshots and soak testing
6. After QA passes, enter improvement mode — research, add new features, and loop again
7. The stop gate blocks Claude from stopping at every stage

## The Loop

```
┌─────────────────────────────────────────────────────────────┐
│                     FEATURES FAILING                        │
│                                                             │
│  1. dependency-graph.py --ready → identify parallel batch   │
│  2. Spawn feature-builder subagents in worktrees            │
│  3. Merge branches → run tests → update features.json       │
│  4. Repeat until all pass                                   │
│                         │                                   │
│                         ▼                                   │
│                      QA MODE                                │
│                                                             │
│  1. Generate qa-report.json from features.json              │
│  2. Walk every user flow, screenshot every step             │
│  3. Visual checklist: layout, typography, spacing, dark mode│
│  4. Soak test: use the app like a real user                 │
│  5. Fix issues, re-verify, mark flows verified              │
│                         │                                   │
│                         ▼                                   │
│                  IMPROVEMENT MODE                           │
│                                                             │
│  1. Research UX polish and competitive analysis             │
│  2. Add 3-5 new features to features.json                  │
│  3. Loop back to Features Failing                           │
└─────────────────────────────────────────────────────────────┘
```

## How It Works

### `features.json` — The Feature Spec

A JSON file listing every feature with test steps and a dependency graph. Each feature has a `depends_on` array that controls build order and parallelization.

```json
{
  "id": "ui-001",
  "description": "User login screen",
  "phase": "mvp",
  "category": "ui",
  "depends_on": ["core-001", "service-001"],
  "passes": false,
  "test_steps": ["Launch app", "Tap login", "Enter credentials", "Verify home screen"]
}
```

Features with all dependencies satisfied are grouped into parallel batches. Features within a batch can be built simultaneously.

### `CLAUDE.md` — The Loop Instructions

Project instructions that tell Claude to:
- Never stop and ask "should I continue?"
- Parallelize aggressively using the dependency graph
- Follow TDD strictly (test first, then implement)
- Complete mandatory QA with screenshots after all features pass

### `scripts/stop-gate.sh` — The Stop Gate

A hook that runs every time Claude tries to stop. It enforces the 3-state loop:

| State | Condition | Behavior |
|-------|-----------|----------|
| **Features Failing** | Incomplete features exist | Block stop, show next batch with parallel info |
| **QA Mode** | All features pass, QA incomplete | Block stop, inject QA protocol |
| **Improvement Mode** | All features + QA pass | Block stop, inject research prompt |

The stop gate is dependency-aware — it shows which features are ready to build in parallel and which are blocked.

### `.claude/agents/feature-builder.md` — The Subagent

A custom subagent with `isolation: worktree` that implements a single feature in its own git worktree branch. Each subagent:
- Gets its own isolated copy of the repo
- Follows TDD strictly
- Commits its work to its branch
- Returns results to the orchestrator for merging

### `scripts/dependency-graph.py` — The Scheduler

Analyzes `features.json` and computes parallelizable work batches via topological sort:

```bash
python3 scripts/dependency-graph.py --ready      # Next parallel batch
python3 scripts/dependency-graph.py --validate    # Check for cycles/missing deps
python3 scripts/dependency-graph.py               # All batches
python3 scripts/dependency-graph.py --dot         # Graphviz visualization
```

### `scripts/stop-gate-prompts.md` — Customizable Prompts

All prompts the agent sees at each loop state are extracted into a markdown file with template variables. Edit this file to change the agent's behavior without touching shell scripts.

## Quick Start

1. Copy this folder into your project root
2. Replace `{{PROJECT_NAME}}`, `{{SIMULATOR_UUID}}`, `{{BUNDLE_ID}}` in `CLAUDE.md` and `init.sh`
3. Define your features in `features.json` with `depends_on` for the dependency graph
4. Run `python3 scripts/dependency-graph.py --validate` to check the graph
5. Uncomment the hooks in `.claude/settings.json`
6. Run Claude Code and say: "Start the development loop"

## File Structure

```
.claude/
  settings.json                # Hooks configuration (stop gate + build-on-edit)
  agents/
    feature-builder.md         # Subagent for parallel feature implementation
CLAUDE.md                      # Project instructions for Claude
features.json                  # Feature specs with dependency graph
claude-progress.md             # Session progress tracking (auto-updated)
qa-report.json                 # QA verification report (auto-generated)
init.sh                        # Environment bootstrap script
.gitignore                     # Excludes worktrees, build artifacts, screenshots
scripts/
  stop-gate.sh                 # 3-state loop enforcement (features → QA → improvement)
  stop-gate-prompts.md         # Customizable prompts for each loop state
  dependency-graph.py          # Dependency analysis and parallel batch scheduling
  qa-check.sh                  # QA report status checker
  check-architecture.sh        # Layer dependency rule enforcement
docs/
  architecture.md              # Architecture layers and rules
  conventions.md               # Code conventions
  testing-strategy.md          # Test layers: unit → integration → XCUITest → QA
  swiftui-testing-best-practices.md  # iOS testing patterns and pitfalls
  qa-strategy.md               # QA phase: flows, visual checklist, soak testing
  parallel-development.md      # Parallel agents, worktrees, orchestration protocol
screenshots/                   # QA screenshots (auto-generated, gitignored)
```

## Customization

### Adapt to Your Stack

This template is iOS/Swift-focused but the loop pattern works for any stack:

1. Replace `swift build` / `swift test` with your build/test commands in `stop-gate.sh` and `init.sh`
2. Replace XCUITest references with your UI testing framework
3. Adjust `features.json` categories for your domain
4. Modify architecture layers in `docs/architecture.md`
5. Update `docs/conventions.md` and `docs/testing-strategy.md`

### Tune Parallelization

- Edit `depends_on` in features to control the dependency graph
- Add `files` arrays to features for conflict detection
- Adjust max parallel agents in `docs/parallel-development.md` (default: 3-4)
- Modify the `feature-builder` subagent in `.claude/agents/feature-builder.md`

### Customize Loop Prompts

Edit `scripts/stop-gate-prompts.md` to change what the agent sees at each state. Template variables are substituted automatically. No need to touch the shell scripts.

### Disable QA Phase

If you don't need the QA phase, create an empty `qa-report.json` with `{"status": "passed"}` and the loop will skip directly to improvement mode.

## Results

In testing with an iOS mental math trainer app:
- 186 features implemented autonomously
- 563 unit tests + 170 UI tests
- 24 development cycles in a single day
- Zero human intervention during feature implementation
