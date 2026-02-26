---
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
argument-hint: "[research topic or question]"
---

# /parallel-research -- Parallel Web Research via tmux + claude -p

Decompose a research question into MECE domains, spawn parallel Claude
agents in tmux panes (up to 12), each running `claude -p` with
pre-approved web tools. Collect findings into structured output files.

## Argument

A research topic or question to investigate broadly. Example:
"state of agentic coding patterns Dec 2025 - Feb 2026"

## Procedure

### Phase 1 -- Understand

Clarify the research question. Identify:
- The core topic
- The timeframe
- How many dimensions / angles the user wants covered
- Whether the user wants adversarial / contrarian coverage

If unclear, ask the user before proceeding.

### Phase 2 -- Decompose into MECE Domains

Split the research into 3-6 independent domains. For each domain,
create 2-3 search variants (a/b/c) that approach the same domain from
different angles. This multiplies coverage without redundancy.

Decomposition rules:
- Divide by **research domain**, NOT by source type. Each agent owns
  a vertical slice of a topic (e.g., "enterprise adoption", "failure
  stories"), not a horizontal layer (e.g., "find all tweets", "find
  all blogs"). Horizontal decomposition causes massive redundancy.
- Each variant within a domain should use different search terms and
  angles to maximize coverage.
- All domains together should be collectively exhaustive -- no gaps.

Present the decomposition table and wait for user approval:

```
| Domain | Agent A (Variant) | Agent B (Variant) |
|--------|-------------------|-------------------|
| Voices | Social media power users | Industry leaders & engineers |
| Blogs  | Workflow pattern posts | Code quality problem posts |
| Critics | Failure postmortems | Skeptics & contrarians |
```

Do NOT proceed until the user approves this decomposition.

### Phase 3 -- Create Agent Directories and Prompts

Create the directory structure:

```bash
mkdir -p research-agents/{agent-name-a,agent-name-b,...}
mkdir -p research-agents/outputs
```

For each agent, write `research-agents/{agent-name}/prompt.md` with
this structure:

```markdown
You are a research agent. DO NOT modify any files in any codebase.
Your ONLY job is to search the web and compile findings.

# Mission: [Specific research goal for this agent]

## Search Strategy
[10+ specific search queries, tailored to this agent's angle]

## What to Capture
[Structured template: what fields to record per finding]

## Output Format
[How to organize the output -- categories, ranking, etc.]
```

Prompt design rules:
- **Always** start with "DO NOT modify any files" -- prevents agents
  from touching code
- **10+ search queries per agent** -- ensures breadth
- **Structured output format** -- makes aggregation possible later
- **Variance between a/b agents** -- different search terms for the
  same domain to catch what the other misses

### Phase 4 -- Create Launcher Script

Write `research-agents/run-agent.sh`:

```bash
#!/bin/bash
cd "$1"
echo "=== Starting research agent: $(basename $1) ==="
echo "=== $(date) ==="
echo ""
cat prompt.md | claude -p \
  --allowedTools "WebSearch,WebFetch,Bash,Read,Write,Grep,Glob" \
  2>&1 | tee output.md
echo ""
echo "=== Agent $(basename $1) COMPLETE at $(date) ==="
```

Make it executable: `chmod +x research-agents/run-agent.sh`

CRITICAL details in this script:
- **Pipe prompt via stdin** (`cat prompt.md | claude -p`). NEVER pass
  the prompt as a positional argument after `--allowedTools` -- the
  variadic flag will consume it as a tool name.
- **Comma-separated tools** (`"WebSearch,WebFetch,..."`). NEVER use
  spaces -- they cause the same variadic consumption problem.
- **--allowedTools is mandatory**. `claude -p` runs non-interactively
  and cannot prompt for permission approval. Without this flag, every
  WebSearch call gets denied silently and the agent exits with
  "I'm blocked".
- `tee output.md` streams to both the terminal and a file.

### Phase 5 -- Build tmux Session

Calculate layout: ceil(total_agents / 4) windows, 4 panes each.

Create the session one window at a time. **Validate each window before
creating the next.**

```bash
# Create first window
tmux new-session -d -s research -n "{window-name}" -x 220 -y 55
tmux split-window -t research:{window-name}
tmux split-window -t research:{window-name}
tmux split-window -t research:{window-name}
tmux select-layout -t research:{window-name} tiled

# VALIDATE before continuing
tmux list-windows -t research -F "#{window_name}: #{window_panes} panes"
```

Repeat for additional windows with `tmux new-window`.

CRITICAL: **Always validate pane count** after creating each window.
Never proceed to launching agents without confirming the panes exist.
Sending `tmux send-keys` to non-existent panes can crash the tmux
server -- killing ALL tmux sessions on the machine, not just yours.

### Phase 6 -- Launch Agents

Send the launcher command to each pane, one window at a time:

```bash
BASE="$(pwd)/research-agents"
L="$BASE/run-agent.sh"

tmux send-keys -t research:{window}.0 "bash $L $BASE/{agent-a}" Enter
tmux send-keys -t research:{window}.1 "bash $L $BASE/{agent-b}" Enter
tmux send-keys -t research:{window}.2 "bash $L $BASE/{agent-c}" Enter
tmux send-keys -t research:{window}.3 "bash $L $BASE/{agent-d}" Enter
```

After launching all agents, verify the processes are running:

```bash
ps aux | grep "claude -p" | grep -v grep | wc -l
```

The count should match the number of agents launched.

Print monitoring instructions for the user:

```
## Parallel Research Agents Running

Attach to session:     tmux attach -t research
Switch windows:        Ctrl-b n (next) / Ctrl-b p (previous)
Switch panes:          Ctrl-b + arrow keys
Zoom a pane:           Ctrl-b z (toggle)
Kill session:          tmux kill-session -t research

Check progress:
  ls -la research-agents/*/output.md
```

### Phase 7 -- Monitor and Collect

When the user asks to check progress, run:

```bash
for agent in {list-of-agents}; do
  dir="research-agents/$agent"
  if [ -s "$dir/output.md" ]; then
    bytes=$(wc -c < "$dir/output.md")
    echo "$agent: ${bytes} bytes"
  else
    echo "$agent: still running..."
  fi
done
```

Note: `tee` buffers lazily. Empty output files for 30-60 seconds is
normal while agents are doing web searches. Verify processes are alive
with `ps aux | grep "claude -p"` rather than relying on file sizes.

When all agents have completed, report the final output sizes and
offer to aggregate findings into a single summary document.

## Important

- Always decompose by **research domain**, never by source type.
- Always wait for user approval of the decomposition before creating
  directories.
- NEVER pass the prompt as a positional argument to `claude -p` after
  `--allowedTools`. Always pipe via stdin.
- NEVER use space-separated tool names in `--allowedTools`. Always use
  commas.
- ALWAYS validate tmux panes exist before sending commands to them.
  Validate after each window creation, not at the end.
- ALWAYS launch one window of agents at a time. Verify that window's
  panes are alive before moving to the next window.
- The tmux session name is `research`. Do not reuse a session name
  that already exists -- check with `tmux has-session -t research`
  first and pick a different name if it exists.
- Do NOT modify any files in the codebase. This skill is research-only.

