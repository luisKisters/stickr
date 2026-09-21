#!/bin/bash
# Runs one phase of PLAN.md with Codex CLI. The model is the Codex default on this Mac (GLM 5.3 Flash).
# usage: scripts/run-phase.sh 1
set -euo pipefail
cd "$(dirname "$0")/.."
PHASE="${1:?give a phase number, for example: scripts/run-phase.sh 1}"
mkdir -p reports
codex exec --dangerously-bypass-approvals-and-sandbox -C "$PWD" -- \
"Read PLAN.md completely. Then do Phase ${PHASE} and nothing else. Obey the sections 'What Luis wants', 'What Luis does not want', 'Verified facts' and 'Rules for the code and the UI'. Run every check listed under 'Done when' for this phase and paste the real command output into reports/phase-${PHASE}.md. If a check fails, fix the cause and run it again. If a check still fails after three attempts, stop and write what failed and why at the top of the report. Never mark a check as passed without its output." \
  < /dev/null 2>&1 | tee "reports/phase-${PHASE}.log"
