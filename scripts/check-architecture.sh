#!/bin/bash
# check-architecture.sh — Enforce layer dependency rules
# Run in CI and as a pre-commit hook.
#
# Layer rules:
#   Domain    -> zero dependencies (no Services, Features, App imports)
#   Services  -> depends on Domain only
#   Features  -> depends on Domain + Services (never other Features)
#   App       -> can depend on anything

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ERRORS=0

check_violations() {
    local layer="$1"
    local forbidden_pattern="$2"
    local fix_message="$3"
    local search_dir="$PROJECT_DIR/Sources/$layer"

    if [ ! -d "$search_dir" ]; then
        return 0
    fi

    violations=$(grep -rn "$forbidden_pattern" "$search_dir" 2>/dev/null || true)
    if [ -n "$violations" ]; then
        echo ""
        echo "ERROR: Layer violation in $layer"
        echo "$violations"
        echo ""
        echo "FIX: $fix_message"
        echo "SEE: docs/architecture.md#layer-dependency-rules"
        ERRORS=$((ERRORS + 1))
    fi
}

echo "=== Checking Architecture Layer Rules ==="

# Domain must not import Services, Features, or App
check_violations "Domain" "import Services\|import Features\|import App" \
    "Domain layer must have zero dependencies. Move the dependency to Services or Features layer."

# Services must not import Features or App
check_violations "Services" "import Features\|import App" \
    "Services layer can only depend on Domain. Inject Feature/App dependencies via protocols defined in Domain."

# Features must not import App
check_violations "Features" "import App" \
    "Features layer cannot depend on App. Use dependency injection from the composition root."

# Features must not import other Features directly
if [ -d "$PROJECT_DIR/Sources/Features" ]; then
    for feature_dir in "$PROJECT_DIR/Sources/Features"/*/; do
        if [ ! -d "$feature_dir" ]; then continue; fi
        feature_name=$(basename "$feature_dir")
        for other_dir in "$PROJECT_DIR/Sources/Features"/*/; do
            if [ ! -d "$other_dir" ]; then continue; fi
            other_name=$(basename "$other_dir")
            if [ "$feature_name" != "$other_name" ]; then
                violations=$(grep -rn "import.*$other_name" "$feature_dir" 2>/dev/null || true)
                if [ -n "$violations" ]; then
                    echo ""
                    echo "ERROR: Cross-feature dependency: $feature_name imports $other_name"
                    echo "$violations"
                    echo ""
                    echo "FIX: Features must not import other Features directly."
                    echo "     Use a shared Service or Domain protocol for cross-feature communication."
                    echo "SEE: docs/architecture.md#features-layer"
                    ERRORS=$((ERRORS + 1))
                fi
            fi
        done
    done
fi

# No print() in production code
if [ -d "$PROJECT_DIR/Sources" ]; then
    prints=$(grep -rn "print(" "$PROJECT_DIR/Sources" --include="*.swift" 2>/dev/null | grep -v "// swiftlint:disable" || true)
    if [ -n "$prints" ]; then
        echo ""
        echo "WARNING: print() found in production code"
        echo "$prints"
        echo ""
        echo "FIX: Use os.Logger instead of print(). See docs/conventions.md#logging"
    fi
fi

if [ $ERRORS -gt 0 ]; then
    echo ""
    echo "=== $ERRORS architecture violation(s) found ==="
    exit 1
else
    echo "=== All architecture rules OK ==="
fi
