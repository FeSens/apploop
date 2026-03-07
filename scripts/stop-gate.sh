#!/bin/bash
# stop-gate.sh — Block agent from stopping while work remains.
# 3 states: Features Failing → QA Mode → Improvement Mode
# Stop hooks: exit 0 = allow stop, exit 2 = block stop (reason on stderr).

set -o pipefail

# Read hook input from stdin (stop hook API)
HOOK_INPUT=$(cat)

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

PROMPTS_FILE="$PROJECT_DIR/scripts/stop-gate-prompts.md"

# --- Helper: extract prompt from markdown section ---
# Usage: extract_prompt "## Section Name"
# Extracts text between ``` fences under the given heading.
extract_prompt() {
  local section="$1"
  if [ -f "$PROMPTS_FILE" ]; then
    awk -v sec="$section" '
      $0 == sec { found=1; next }
      found && /^## / { exit }
      found && /^```$/ { if (infence) exit; infence=1; next }
      found && infence { print }
    ' "$PROMPTS_FILE"
  else
    echo "(prompts file not found at scripts/stop-gate-prompts.md)"
  fi
}

# --- Helper: substitute template variables in a string ---
# Usage: result=$(template_sub "$template" "KEY" "VALUE")
template_sub() {
  local text="$1" key="$2" val="$3"
  echo "$text" | sed "s|{{${key}}}|${val}|g"
}

# Detect project type: SPM (Package.swift) or Xcode project (.xcodeproj/.xcworkspace)
PROJECT_TYPE=""
if [ -f "Package.swift" ]; then
  PROJECT_TYPE="spm"
elif ls *.xcodeproj 1>/dev/null 2>&1 || ls *.xcworkspace 1>/dev/null 2>&1; then
  PROJECT_TYPE="xcode"
fi

# Skip all checks if no project exists yet (not scaffolded)
if [ -z "$PROJECT_TYPE" ]; then
  exit 0
fi

ISSUES=""
ACTIONS=""

# 1. Build check
if [ "$PROJECT_TYPE" = "spm" ]; then
  if ! swift build >/dev/null 2>&1; then
    ISSUES="${ISSUES}build_failure "
    ACTIONS="${ACTIONS}>> IMMEDIATE: Fix the build error. Run 'swift build' to see full errors.\n"
  fi
else
  XCPROJ=$(ls -d *.xcodeproj 2>/dev/null | head -1)
  SCHEME="${XCPROJ%.xcodeproj}"
  if [ -n "$XCPROJ" ] && ! xcodebuild build -project "$XCPROJ" -scheme "$SCHEME" -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>/dev/null; then
    ISSUES="${ISSUES}build_failure "
    ACTIONS="${ACTIONS}>> IMMEDIATE: Fix the build error. Run 'xcodebuild build' to see full errors.\n"
  fi
fi

# 2. Test check
if [ "$PROJECT_TYPE" = "spm" ]; then
  if ! swift test >/dev/null 2>&1; then
    ISSUES="${ISSUES}test_failure "
    ACTIONS="${ACTIONS}>> IMMEDIATE: Fix failing tests. Run 'swift test' to see which tests fail.\n"
  fi
else
  XCPROJ=$(ls -d *.xcodeproj 2>/dev/null | head -1)
  SCHEME="${XCPROJ%.xcodeproj}"
  if [ -n "$XCPROJ" ] && ! xcodebuild test -project "$XCPROJ" -scheme "$SCHEME" -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>/dev/null; then
    ISSUES="${ISSUES}test_failure "
    ACTIONS="${ACTIONS}>> IMMEDIATE: Fix failing tests. Run 'xcodebuild test' to see which tests fail.\n"
  fi
fi

# 3. Architecture check
if [ -f "$PROJECT_DIR/scripts/check-architecture.sh" ]; then
  if ! bash "$PROJECT_DIR/scripts/check-architecture.sh" >/dev/null 2>&1; then
    ISSUES="${ISSUES}arch_violation "
    ACTIONS="${ACTIONS}>> IMMEDIATE: Fix architecture violations.\n"
  fi
fi

# 4. Uncommitted changes
UNCOMMITTED=$(git status --porcelain 2>/dev/null)
if [ -n "$UNCOMMITTED" ]; then
  ISSUES="${ISSUES}uncommitted_changes "
  ACTIONS="${ACTIONS}>> ACTION: Commit your changes before continuing.\n$(git status --short 2>/dev/null)\n"
fi

# 5. Check features.json for next failing feature
NEXT_PROMPT=""
PASSING=0
TOTAL=0
FAILING=0

if [ -f "$PROJECT_DIR/features.json" ]; then
  FEATURE_STATUS=$(python3 -c "
import json
from collections import defaultdict, deque

with open('$PROJECT_DIR/features.json') as f:
    data = json.load(f)
features = data.get('features', [])
total = len(features)
passing = sum(1 for f in features if f.get('passes', False))
failing = [f for f in features if not f.get('passes', False)]
print(f'TOTAL={total}')
print(f'PASSING={passing}')
print(f'FAILING={len(failing)}')

# Compute ready batch (deps satisfied, not yet passing)
passing_ids = {f['id'] for f in features if f.get('passes', False)}
ready = []
blocked = []
for f in failing:
    deps = set(f.get('depends_on', []))
    if deps <= passing_ids:
        ready.append(f)
    else:
        missing = deps - passing_ids
        blocked.append((f, missing))

print(f'READY_COUNT={len(ready)}')
print(f'BLOCKED_COUNT={len(blocked)}')

if ready:
    nxt = ready[0]
    print(f'NEXT_ID={nxt[\"id\"]}')
    print(f'NEXT_PHASE={nxt.get(\"phase\", \"\")}')
    print(f'NEXT_DESC={nxt.get(\"description\", \"\")}')
    steps = ' | '.join(nxt.get('test_steps', []))
    print(f'NEXT_STEPS={steps}')
    # Show all ready features for parallel execution
    for f in ready[1:]:
        cat = f.get('category', f.get('phase', ''))
        print(f'PARALLEL={f[\"id\"]}: {f.get(\"description\", \"\")} [{cat}]')
    # Show upcoming blocked features
    for f, missing in blocked[:3]:
        print(f'UPCOMING={f[\"id\"]}: {f.get(\"description\", \"\")} (blocked by: {\", \".join(missing)})')
" 2>/dev/null) || true

  TOTAL=$(echo "$FEATURE_STATUS" | grep '^TOTAL=' | cut -d= -f2- || echo "0")
  PASSING=$(echo "$FEATURE_STATUS" | grep '^PASSING=' | cut -d= -f2- || echo "0")
  FAILING=$(echo "$FEATURE_STATUS" | grep '^FAILING=' | cut -d= -f2- || echo "0")
  READY_COUNT=$(echo "$FEATURE_STATUS" | grep '^READY_COUNT=' | cut -d= -f2- || echo "0")
  NEXT_ID=$(echo "$FEATURE_STATUS" | grep '^NEXT_ID=' | cut -d= -f2- || echo "")
  NEXT_PHASE=$(echo "$FEATURE_STATUS" | grep '^NEXT_PHASE=' | cut -d= -f2- || echo "")
  NEXT_DESC=$(echo "$FEATURE_STATUS" | grep '^NEXT_DESC=' | cut -d= -f2- || echo "")
  NEXT_STEPS=$(echo "$FEATURE_STATUS" | grep '^NEXT_STEPS=' | cut -d= -f2- || echo "")
  PARALLEL=$(echo "$FEATURE_STATUS" | grep '^PARALLEL=' | cut -d= -f2- || echo "")
  UPCOMING=$(echo "$FEATURE_STATUS" | grep '^UPCOMING=' | cut -d= -f2- || echo "")

  if [ "$FAILING" -gt 0 ] 2>/dev/null; then
    ISSUES="${ISSUES}incomplete_features "
    NEXT_PROMPT="NEXT FEATURE: $NEXT_ID ($NEXT_PHASE) - $NEXT_DESC | Test steps: $NEXT_STEPS | TDD Loop: Write failing test -> Implement -> Run tests -> Verify -> Commit -> Next"
    if [ "$READY_COUNT" -gt 1 ] 2>/dev/null; then
      NEXT_PROMPT="$NEXT_PROMPT | PARALLEL READY ($READY_COUNT features can run simultaneously): $(echo "$PARALLEL" | tr '\n' ', ') | Use feature-builder subagents in worktrees for parallel execution (see docs/parallel-development.md)"
    fi
    if [ -n "$UPCOMING" ]; then
      NEXT_PROMPT="$NEXT_PROMPT | Blocked: $(echo "$UPCOMING" | tr '\n' ', ')"
    fi
  fi
fi

# ============================================================
# STATE 1: Features Failing — keep implementing
# ============================================================

if [ -n "$ISSUES" ]; then
  TEMPLATE=$(extract_prompt "## Features Failing")
  if [ -z "$TEMPLATE" ]; then
    TEMPLATE="STOP BLOCKED - Progress: {{PASSING}}/{{TOTAL}} features passing.\n{{ACTIONS}}\n{{NEXT_PROMPT}}\nDO NOT STOP. Continue working."
  fi

  REASON=$(template_sub "$TEMPLATE" "PASSING" "$PASSING")
  REASON=$(template_sub "$REASON" "TOTAL" "$TOTAL")

  ACTIONS_EXPANDED=$(echo -e "$ACTIONS")
  if [ -n "$ACTIONS_EXPANDED" ]; then
    REASON=$(echo "$REASON" | sed "s|{{ACTIONS}}|$ACTIONS_EXPANDED|")
  else
    REASON=$(echo "$REASON" | sed "s|{{ACTIONS}}||")
  fi

  if [ -n "$NEXT_PROMPT" ]; then
    REASON=$(echo "$REASON" | sed "s|{{NEXT_PROMPT}}|$NEXT_PROMPT|")
  else
    REASON=$(echo "$REASON" | sed "s|{{NEXT_PROMPT}}||")
  fi

  echo "$REASON" >&2
  exit 2
fi

# ============================================================
# All features pass, no build/test issues, no uncommitted changes.
# Now decide: QA Mode or Improvement Mode?
# ============================================================

# 6. Check QA status
QA_STATUS="not_started"
QA_VERIFIED=0
QA_TOTAL=0
QA_NEXT_FLOW=""
QA_NEXT_NAME=""
QA_NEXT_STEPS_DONE=0
QA_NEXT_STEPS_TOTAL=0
QA_NEXT_CHECKS="0/0"

if [ -f "$PROJECT_DIR/scripts/qa-check.sh" ]; then
  QA_OUTPUT=$(bash "$PROJECT_DIR/scripts/qa-check.sh" 2>/dev/null) || true
  QA_STATUS=$(echo "$QA_OUTPUT" | grep '^QA_STATUS=' | cut -d= -f2- || echo "not_started")
  QA_VERIFIED=$(echo "$QA_OUTPUT" | grep '^QA_VERIFIED=' | cut -d= -f2- || echo "0")
  QA_TOTAL=$(echo "$QA_OUTPUT" | grep '^QA_TOTAL=' | cut -d= -f2- || echo "0")
  QA_NEXT_FLOW=$(echo "$QA_OUTPUT" | grep '^QA_NEXT_FLOW=' | cut -d= -f2- || echo "")
  QA_NEXT_NAME=$(echo "$QA_OUTPUT" | grep '^QA_NEXT_NAME=' | cut -d= -f2- || echo "")
  QA_NEXT_STEPS_DONE=$(echo "$QA_OUTPUT" | grep '^QA_NEXT_STEPS_DONE=' | cut -d= -f2- || echo "0")
  QA_NEXT_STEPS_TOTAL=$(echo "$QA_OUTPUT" | grep '^QA_NEXT_STEPS_TOTAL=' | cut -d= -f2- || echo "0")
  QA_NEXT_CHECKS=$(echo "$QA_OUTPUT" | grep '^QA_NEXT_CHECKS=' | cut -d= -f2- || echo "0/0")
fi

# ============================================================
# STATE 2: QA Mode — all features pass, QA not complete
# ============================================================

if [ "$QA_STATUS" != "passed" ]; then
  TEMPLATE=$(extract_prompt "## QA Mode")
  if [ -z "$TEMPLATE" ]; then
    TEMPLATE="ALL FEATURES PASSING. Entering QA MODE. Read docs/qa-strategy.md. QA Progress: {{QA_VERIFIED}}/{{QA_TOTAL}} flows verified. DO NOT STOP."
  fi

  REASON=$(template_sub "$TEMPLATE" "QA_VERIFIED" "$QA_VERIFIED")
  REASON=$(template_sub "$REASON" "QA_TOTAL" "$QA_TOTAL")
  REASON=$(template_sub "$REASON" "QA_NEXT_FLOW" "$QA_NEXT_FLOW")
  REASON=$(template_sub "$REASON" "QA_NEXT_NAME" "$QA_NEXT_NAME")
  REASON=$(template_sub "$REASON" "QA_NEXT_STEPS_DONE" "$QA_NEXT_STEPS_DONE")
  REASON=$(template_sub "$REASON" "QA_NEXT_STEPS_TOTAL" "$QA_NEXT_STEPS_TOTAL")
  REASON=$(template_sub "$REASON" "QA_NEXT_CHECKS" "$QA_NEXT_CHECKS")

  echo "$REASON" >&2
  exit 2
fi

# ============================================================
# STATE 3: Improvement Mode — all features pass AND QA verified
# ============================================================

TEMPLATE=$(extract_prompt "## All Passing (QA Complete)")
if [ -z "$TEMPLATE" ]; then
  TEMPLATE="ALL FEATURES PASSING. QA VERIFIED. Enter improvement mode."
fi

echo "$TEMPLATE" >&2
exit 2
