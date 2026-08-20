#!/usr/bin/env bash
# Live, human-readable feed of DefenseClaw events. Run it in a spare
# terminal, then have Claude Code do anything: each tool call shows up
# as a tool.activity line followed by its guardrail.evaluation verdict.
# HIGH severity lines are pattern matches (see runbook/03).
#
# The feed reads the local-events JSONL destination configured in
# ~/.defenseclaw/config.yaml. Ctrl+C to stop.
set -euo pipefail

EVENTS_FILE="${HOME}/.defenseclaw/events.jsonl"

if [[ ! -f "${EVENTS_FILE}" ]]; then
  echo "Missing ${EVENTS_FILE}." >&2
  echo "Check the local-events destination in ~/.defenseclaw/config.yaml." >&2
  exit 1
fi

# Fields vary per bucket, so every access needs a fallback. -u keeps
# python unbuffered so events appear the moment they are written.
tail -f "${EVENTS_FILE}" | python3 -u -c '
import json
import sys

for line in sys.stdin:
    try:
        event = json.loads(line)
    except ValueError:
        continue
    timestamp = (event.get("observed_at") or event.get("timestamp") or "-")[11:19]
    name = event.get("event_name") or event.get("action") or "-"
    severity = event.get("severity", "-")
    bucket = event.get("bucket", "-")
    print(f"{timestamp:<9} {severity:<8} {bucket:<22} {name}")
'
