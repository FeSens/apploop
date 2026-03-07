#!/bin/bash
# find-simulator.sh — Auto-detect the best available iOS Simulator destination.
# Outputs a destination string suitable for xcodebuild -destination.
#
# Priority:
#   1. Booted simulator (already running)
#   2. Any available iPhone simulator (newest runtime, prefer Pro models)
#
# Usage:
#   DEST=$(bash scripts/find-simulator.sh)
#   xcodebuild build -destination "$DEST" ...

set -o pipefail

# 1. Check for a booted simulator first
BOOTED_UDID=$(xcrun simctl list devices booted -j 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data.get('devices', {}).items():
    for d in devices:
        if d.get('state') == 'Booted' and 'iPhone' in d.get('name', ''):
            print(d['udid'])
            sys.exit(0)
# No iPhone booted, take any booted device
for runtime, devices in data.get('devices', {}).items():
    for d in devices:
        if d.get('state') == 'Booted':
            print(d['udid'])
            sys.exit(0)
" 2>/dev/null)

if [ -n "$BOOTED_UDID" ]; then
  echo "id=$BOOTED_UDID"
  exit 0
fi

# 2. Find the best available iPhone simulator
BEST=$(xcrun simctl list devices available -j 2>/dev/null | python3 -c "
import json, sys, re

data = json.load(sys.stdin)
candidates = []
for runtime, devices in data.get('devices', {}).items():
    # Extract iOS version from runtime string
    m = re.search(r'iOS[- ](\d+)[.-](\d+)', runtime)
    if not m:
        continue
    ver = (int(m.group(1)), int(m.group(2)))
    for d in devices:
        if d.get('isAvailable') and 'iPhone' in d.get('name', ''):
            # Prefer Pro models, then plain numbers (iPhone 16 > iPhone SE)
            name = d['name']
            pro = 1 if 'Pro' in name else 0
            num = 0
            nm = re.search(r'iPhone (\d+)', name)
            if nm:
                num = int(nm.group(1))
            candidates.append((ver, pro, num, d['udid'], name))

if not candidates:
    sys.exit(1)

candidates.sort(reverse=True)
best = candidates[0]
print(best[3])  # udid
" 2>/dev/null)

if [ -n "$BEST" ]; then
  echo "id=$BEST"
  exit 0
fi

# 3. Fallback — generic platform destination (let xcodebuild pick)
echo "platform=iOS Simulator,name=iPhone 16"
