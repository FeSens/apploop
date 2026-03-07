#!/usr/bin/env python3
"""Analyze features.json dependency graph and output parallelizable work batches.

Usage:
    python3 scripts/dependency-graph.py              # Show all batches
    python3 scripts/dependency-graph.py --ready       # Show only the next ready batch
    python3 scripts/dependency-graph.py --validate    # Check for cycles and missing deps
    python3 scripts/dependency-graph.py --dot         # Output Graphviz DOT format

Output format (default):
    BATCH=1
    FEATURE=core-001|phase|description|layer
    FEATURE=core-002|phase|description|layer
    BATCH=2
    FEATURE=ui-001|phase|description|layer
    ...

Used by the orchestrator to determine which features can be built in parallel.
"""

import json
import sys
from collections import defaultdict, deque
from pathlib import Path


def load_features(path="features.json"):
    with open(path) as f:
        data = json.load(f)
    return data.get("features", [])


def validate(features):
    """Check for cycles, missing dependencies, and self-references."""
    ids = {f["id"] for f in features}
    errors = []

    for f in features:
        fid = f["id"]
        deps = f.get("depends_on", [])

        if fid in deps:
            errors.append(f"SELF_REF: {fid} depends on itself")

        for dep in deps:
            if dep not in ids:
                errors.append(f"MISSING_DEP: {fid} depends on '{dep}' which doesn't exist")

    # Cycle detection (Kahn's algorithm)
    in_degree = defaultdict(int)
    graph = defaultdict(list)
    for f in features:
        fid = f["id"]
        for dep in f.get("depends_on", []):
            graph[dep].append(fid)
            in_degree[fid] += 1
        if fid not in in_degree:
            in_degree[fid] = 0

    queue = deque([fid for fid, deg in in_degree.items() if deg == 0])
    visited = 0
    while queue:
        node = queue.popleft()
        visited += 1
        for neighbor in graph[node]:
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                queue.append(neighbor)

    if visited < len(features):
        errors.append("CYCLE: Dependency cycle detected — cannot determine build order")

    return errors


def compute_batches(features):
    """Topological sort into parallelizable batches.

    Each batch contains features whose dependencies are ALL in previous batches
    (or already passing). Features within a batch can be built in parallel.
    """
    feature_map = {f["id"]: f for f in features}
    passing = {f["id"] for f in features if f.get("passes", False)}
    remaining = {f["id"] for f in features if not f.get("passes", False)}
    satisfied = set(passing)
    batches = []

    while remaining:
        # Find features whose deps are all satisfied
        ready = set()
        for fid in remaining:
            deps = set(feature_map[fid].get("depends_on", []))
            if deps <= satisfied:
                ready.add(fid)

        if not ready:
            # Deadlock — remaining features have unsatisfied deps (cycle or missing)
            break

        batches.append(sorted(ready))
        satisfied |= ready
        remaining -= ready

    return batches


def layer_for_feature(feature):
    """Infer the architecture layer from feature id/category."""
    fid = feature.get("id", "")
    cat = feature.get("category", "")
    if "domain" in fid or "domain" in cat or "model" in fid:
        return "domain"
    if "service" in fid or "service" in cat:
        return "services"
    if "ui" in fid or "ui" in cat or "view" in fid:
        return "features"
    if "core" in fid or "infra" in fid or "setup" in fid:
        return "domain"
    return "unknown"


def main():
    args = set(sys.argv[1:])
    project_dir = Path(__file__).parent.parent
    features_path = project_dir / "features.json"

    if not features_path.exists():
        print("NO_FEATURES_FILE", file=sys.stderr)
        sys.exit(1)

    features = load_features(features_path)

    if not features:
        print("NO_FEATURES")
        sys.exit(0)

    # Validate
    if "--validate" in args:
        errors = validate(features)
        if errors:
            for e in errors:
                print(f"ERROR: {e}")
            sys.exit(1)
        else:
            print("OK: No dependency issues found")
            sys.exit(0)

    # DOT output
    if "--dot" in args:
        print("digraph features {")
        print("  rankdir=LR;")
        for f in features:
            color = "green" if f.get("passes") else "red"
            print(f'  "{f["id"]}" [color={color}, style=filled, fillcolor={"lightgreen" if f.get("passes") else "lightyellow"}];')
            for dep in f.get("depends_on", []):
                print(f'  "{dep}" -> "{f["id"]}";')
        print("}")
        sys.exit(0)

    # Compute batches
    feature_map = {f["id"]: f for f in features}
    batches = compute_batches(features)

    if "--ready" in args:
        # Only show the first batch that has non-passing features
        for batch in batches:
            non_passing = [fid for fid in batch if not feature_map[fid].get("passes", False)]
            if non_passing:
                print(f"BATCH=1")
                for fid in non_passing:
                    f = feature_map[fid]
                    layer = layer_for_feature(f)
                    print(f"FEATURE={fid}|{f.get('phase', '')}|{f.get('description', '')}|{layer}")
                break
    else:
        batch_num = 0
        for batch in batches:
            batch_num += 1
            non_passing = [fid for fid in batch if not feature_map[fid].get("passes", False)]
            if non_passing:
                print(f"BATCH={batch_num}")
                for fid in non_passing:
                    f = feature_map[fid]
                    layer = layer_for_feature(f)
                    status = "PASS" if f.get("passes") else "FAIL"
                    print(f"FEATURE={fid}|{f.get('phase', '')}|{f.get('description', '')}|{layer}|{status}")


if __name__ == "__main__":
    main()
