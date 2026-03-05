#!/usr/bin/env bash
set -euo pipefail

# diagnose-agents.sh -- Classify each pane in a tmux session into one of
# four states: DONE, WORKING, FAILED, UNKNOWN. Prints a per-pane report
# and a summary line.
#
# Algorithm:
#   1. Validate that the given tmux session exists.
#   2. List all panes in the session (across all windows).
#   3. For each pane:
#      a. Check if the pane process is dead (#{pane_dead}).
#      b. Capture the last 50 lines of pane output.
#      c. Check for the COMPLETE marker in the captured text.
#      d. Check for known error patterns (rate limit, traceback,
#         permission denied, "I'm blocked").
#      e. Classify:
#         - DONE     = COMPLETE marker found
#         - FAILED   = process dead without COMPLETE marker,
#                      OR error patterns visible while alive
#         - WORKING  = process alive, no COMPLETE, no errors
#         - UNKNOWN  = pane doesn't exist or capture failed
#   4. If an output dir pattern is provided, also check whether
#      the corresponding output file exists and report its size.
#   5. Print a summary: counts per state.
#
# Args:
#   $1 -- tmux session name (required)
#   $2 -- output dir glob pattern (optional). Example:
#          "research-agents/*/output.md" or "worktrees/*/run/output.md"
#
# Output:
#   Per-pane block with state, PID, last output line.
#   Summary line with counts.

usage() {
  cat <<'USAGE'
Usage: diagnose-agents.sh <session-name> [output-dir-pattern]

Classify each pane in a tmux session into: DONE, WORKING, FAILED, UNKNOWN.

Arguments:
  session-name       tmux session to inspect (required)
  output-dir-pattern glob for output files (optional)
                     e.g. "research-agents/*/output.md"

Examples:
  bash diagnose-agents.sh research
  bash diagnose-agents.sh parallel "worktrees/*/run/output.md"
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

SESSION="$1"
OUTPUT_PATTERN="${2:-}"

# Error patterns that indicate a failed or stuck agent.
# Each pattern is an extended regex matched against the last 50 lines.
ERROR_PATTERNS=(
  "rate limit"
  "Rate limit"
  "RateLimitError"
  "Traceback \\(most recent call last\\)"
  "Error:"
  "permission denied"
  "Permission denied"
  "I'm blocked"
  "EACCES"
  "ENOMEM"
  "killed"
  "Killed"
  "OOMKilled"
)

# Build a single regex from all error patterns (joined with |)
error_regex=""
for pat in "${ERROR_PATTERNS[@]}"; do
  if [[ -z "$error_regex" ]]; then
    error_regex="$pat"
  else
    error_regex="$error_regex|$pat"
  fi
done

# Check session exists
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "ERROR: tmux session '$SESSION' does not exist."
  echo "Active sessions:"
  tmux list-sessions 2>/dev/null || echo "  (none)"
  exit 1
fi

# Counters for summary
count_done=0
count_working=0
count_failed=0
count_unknown=0

# Iterate all panes in the session
PANES=$(tmux list-panes -s -t "$SESSION" -F '#{window_index}.#{pane_index}')

for pane in $PANES; do
  target="$SESSION:$pane"
  echo "=== $target ==="

  # Step 1: Check process liveness via #{pane_dead}
  pane_dead=$(tmux display-message -t "$target" -p '#{pane_dead}' 2>/dev/null || echo "error")

  if [[ "$pane_dead" == "error" ]]; then
    echo "  State: UNKNOWN (pane not accessible)"
    count_unknown=$((count_unknown + 1))
    echo ""
    continue
  fi

  # Get PID for display
  pid=$(tmux display-message -t "$target" -p '#{pane_pid}' 2>/dev/null || echo "?")

  # Step 2: Capture last 50 lines of pane output
  pane_text=$(tmux capture-pane -p -J -t "$target" -S -50 2>/dev/null || echo "")

  # Step 3: Check for COMPLETE marker
  has_complete=false
  if printf '%s\n' "$pane_text" | grep -q "COMPLETE"; then
    has_complete=true
  fi

  # Step 4: Check for error patterns
  has_errors=false
  matched_error=""
  if [[ -n "$pane_text" ]]; then
    matched_error=$(printf '%s\n' "$pane_text" | grep -E -o "$error_regex" 2>/dev/null | head -1 || true)
    if [[ -n "$matched_error" ]]; then
      has_errors=true
    fi
  fi

  # Step 5: Classify
  if $has_complete; then
    state="DONE"
    count_done=$((count_done + 1))
  elif [[ "$pane_dead" == "1" ]]; then
    state="FAILED (process dead, no COMPLETE marker)"
    count_failed=$((count_failed + 1))
  elif $has_errors; then
    state="FAILED (error detected: $matched_error)"
    count_failed=$((count_failed + 1))
  else
    # Process alive, no COMPLETE, no errors
    state="WORKING"
    count_working=$((count_working + 1))
  fi

  # Display
  if [[ "$pane_dead" == "1" ]]; then
    echo "  State: $state"
  else
    echo "  State: $state (pid $pid, alive)"
  fi

  # Last non-blank output line
  last_line=$(printf '%s\n' "$pane_text" | grep -v '^[[:space:]]*$' | tail -1 || true)
  if [[ -n "$last_line" ]]; then
    echo "  Last output: $last_line"
  else
    echo "  Last output: (blank -- agent may be thinking)"
  fi

  echo ""
done

# Output file check (if pattern provided)
if [[ -n "$OUTPUT_PATTERN" ]]; then
  echo "--- Output Files ---"
  # Use eval to expand the glob
  found_any=false
  for f in $OUTPUT_PATTERN; do
    if [[ -f "$f" ]]; then
      found_any=true
      size=$(wc -c < "$f" | tr -d ' ')
      echo "  $f: ${size} bytes"
    fi
  done
  if ! $found_any; then
    echo "  No files matched pattern: $OUTPUT_PATTERN"
  fi
  echo ""
fi

# Summary
total=$((count_done + count_working + count_failed + count_unknown))
echo "Summary: $count_working working, $count_done done, $count_failed failed, $count_unknown unknown (${total} total)"
