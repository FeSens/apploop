#!/bin/bash
# qa-check.sh — Check QA report status.
# Returns: QA_STATUS=not_started|in_progress|passed
#          QA_VERIFIED=N (number of verified flows)
#          QA_TOTAL=N (total flows)
#          QA_NEXT_FLOW=id (next unverified flow id)
#          QA_NEXT_NAME=name (next unverified flow name)

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
QA_REPORT="$PROJECT_DIR/qa-report.json"

if [ ! -f "$QA_REPORT" ]; then
  echo "QA_STATUS=not_started"
  echo "QA_VERIFIED=0"
  echo "QA_TOTAL=0"
  exit 0
fi

python3 -c "
import json, sys

with open('$QA_REPORT') as f:
    data = json.load(f)

status = data.get('status', 'in_progress')
flows = data.get('flows', [])
total = len(flows)
verified = sum(1 for f in flows if f.get('verified', False))
unverified = [f for f in flows if not f.get('verified', False)]

print(f'QA_STATUS={status}')
print(f'QA_VERIFIED={verified}')
print(f'QA_TOTAL={total}')

if unverified:
    nxt = unverified[0]
    print(f'QA_NEXT_FLOW={nxt[\"id\"]}')
    print(f'QA_NEXT_NAME={nxt[\"name\"]}')
    steps_total = len(nxt.get('steps', []))
    steps_done = sum(1 for s in nxt.get('steps', []) if s.get('verified', False))
    print(f'QA_NEXT_STEPS_DONE={steps_done}')
    print(f'QA_NEXT_STEPS_TOTAL={steps_total}')

    # Checklist summary
    checklist = nxt.get('checklist', {})
    checks_done = sum(1 for v in checklist.values() if v)
    checks_total = len(checklist)
    print(f'QA_NEXT_CHECKS={checks_done}/{checks_total}')
" 2>/dev/null || echo "QA_STATUS=error"
