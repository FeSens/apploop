#!/bin/bash
# init.sh — Idempotent environment bootstrap
# Run at the start of every session to ensure a clean, working environment.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "=== {{PROJECT_NAME}} — Environment Setup ==="

# 0. Ensure git is initialized (required for worktrees and parallel agents)
if [ ! -d ".git" ]; then
    echo "Initializing git repository..."
    git init
    git add -A
    git commit -m "Initial commit" --allow-empty 2>/dev/null || true
    echo "  OK"
else
    echo "Git repository: OK"
fi

# 1. Verify Xcode CLI tools
echo "Checking Xcode CLI tools..."
if ! xcode-select -p >/dev/null 2>&1; then
    echo "ERROR: Xcode CLI tools not installed. Run: xcode-select --install"
    exit 1
fi
echo "  OK"

# 2. Verify Swift is available
echo "Checking Swift..."
swift --version 2>/dev/null | head -1
echo "  OK"

# 3. Detect project type and build/test
if [ -f "Package.swift" ]; then
    echo "Detected: Swift Package Manager project"
    echo "Resolving Swift packages..."
    swift package resolve
    echo "  OK"

    echo "Building project..."
    swift build 2>&1 | tail -5
    echo "  OK"

    echo "Running tests (baseline check)..."
    swift test 2>&1 | tail -10
    echo "  OK"
elif XCPROJ=$(ls -d *.xcodeproj 2>/dev/null | head -1); [ -n "$XCPROJ" ]; then
    SCHEME="${XCPROJ%.xcodeproj}"
    echo "Detected: Xcode project ($XCPROJ, scheme: $SCHEME)"

    SIM_DEST=$(bash "$PROJECT_DIR/scripts/find-simulator.sh" 2>/dev/null)
    if [ -z "$SIM_DEST" ]; then
        SIM_DEST="platform=iOS Simulator,name=iPhone 16"
    fi
    echo "Simulator destination: $SIM_DEST"

    echo "Building project..."
    xcodebuild build -project "$XCPROJ" -scheme "$SCHEME" -sdk iphonesimulator \
        -destination "$SIM_DEST" -quiet 2>&1 | tail -5
    echo "  OK"

    echo "Running tests (baseline check)..."
    xcodebuild test -project "$XCPROJ" -scheme "$SCHEME" -sdk iphonesimulator \
        -destination "$SIM_DEST" -quiet 2>&1 | tail -10
    echo "  OK"
else
    echo "No Package.swift or .xcodeproj found — skipping build/test (create project structure first)"
fi

# 6. Validate feature dependency graph
if [ -f "features.json" ] && [ -f "scripts/dependency-graph.py" ]; then
    echo "Validating dependency graph..."
    if python3 scripts/dependency-graph.py --validate 2>/dev/null; then
        echo "  OK"
        echo "Ready batch:"
        python3 scripts/dependency-graph.py --ready 2>/dev/null | head -10
    else
        echo "  WARNING: Dependency graph has issues — run 'python3 scripts/dependency-graph.py --validate' for details"
    fi
fi

echo ""
echo "=== Environment ready ==="
