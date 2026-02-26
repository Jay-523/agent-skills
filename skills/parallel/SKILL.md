---
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
argument-hint: "[task description or 'plan' to use current plan]"
---

# /parallel -- Parallel Agent Orchestration via tmux + git Worktrees

Split a task into independent workstreams and run them as parallel Claude
Code agents in separate tmux panes, each in its own git worktree.

## Argument

Either a task description to plan and decompose, or the word "plan" to
use the current plan from this conversation.

## Procedure

### Phase 1 -- Plan

If the argument is "plan": use the existing plan from the current
conversation context.

Otherwise: create a plan for the given task. Identify what needs to be
built, the modules involved, and the dependencies between them.

### Phase 2 -- Decompose into Workstreams

Split the plan into 3-4 independent workstreams (hard maximum: 4).

Decomposition rules:
- Divide by **domain/module**, NOT by task type. Each agent owns a
  vertical slice (e.g., "auth module", "payment module"), not a
  horizontal layer (e.g., "write all tests", "write all implementations").
  Horizontal decomposition causes 3-10x token waste because each agent
  must re-read the same context.
- Each agent owns its files **exclusively**. No two agents write to the
  same file. Shared dependencies are read-only for non-owning agents.
- If a workstream depends on another's output, mark it and sequence
  the launch accordingly.

Present the decomposition table and wait for user approval:

```
| Agent | Domain | Owned Files | Read-Only Files | Depends On |
|-------|--------|-------------|-----------------|------------|
| auth  | Authentication | src/auth/* | src/models/* | none |
| api   | API endpoints  | src/api/*  | src/auth/*   | auth |
| ui    | Frontend       | src/ui/*   | src/api/*    | none |
```

Do NOT proceed until the user approves this decomposition.

### Phase 3 -- Setup Worktrees

For each agent in the approved decomposition:

```bash
git worktree add ./worktrees/{agent-name} -b parallel/{agent-name}
```

Add `worktrees/` to `.gitignore` if not already present.

For each worktree:
```bash
# Copy environment files
cp .env ./worktrees/{agent-name}/.env 2>/dev/null || true
cp -r venv ./worktrees/{agent-name}/venv 2>/dev/null || true

# Create coordination directories
mkdir -p ./worktrees/{agent-name}/run
mkdir -p ./shared/progress
```

Install dependencies if needed:
```bash
cd ./worktrees/{agent-name} && source venv/bin/activate && uv pip install -e . 2>/dev/null || true
```

### Phase 4 -- Generate Agent Prompts

For each agent, write `./worktrees/{agent-name}/run/prompt.md` containing:

1. **Scope**: What this agent is responsible for building
2. **File Ownership**: Files this agent may create/modify (exclusive)
3. **Read-Only Files**: Files this agent may read but must not modify
4. **Success Criteria**: How to know when the work is done
5. **Constraints**:
   - Follow all CLAUDE.md conventions (copy relevant entries)
   - Add docstrings to all functions with algorithm in English
   - Expected schema for loose objects in docstrings
   - `if __name__ == '__main__'` blocks with hardcoded examples
   - No argparse, no emojis
   - Use `uv pip install`, `source venv/bin/activate`
6. **Progress Tracking**: Write status to
   `../shared/progress/{agent-name}.json` after each major milestone
   using this format:
   ```json
   {
     "agent": "{agent-name}",
     "timestamp": "ISO-8601",
     "status": "in_progress|blocked|done",
     "completed": ["list of completed items"],
     "remaining": ["list of remaining items"],
     "blocked_by": null,
     "notes": ""
   }
   ```

### Phase 5 -- Launch Agents

Create a tmux session and launch agents:

```bash
# Create session
tmux new-session -d -s parallel -x 200 -y 50

# First agent gets the first pane
tmux send-keys -t parallel "cd $(pwd)/worktrees/{agent-1} && claude" Enter

# Additional agents get split panes
tmux split-window -t parallel -h
tmux send-keys -t parallel "cd $(pwd)/worktrees/{agent-2} && claude" Enter

# Repeat for agents 3-4 if needed
tmux split-window -t parallel -v
tmux send-keys -t parallel "cd $(pwd)/worktrees/{agent-3} && claude" Enter
```

After all agents are launched, send each agent its prompt:

```bash
tmux send-keys -t parallel:{pane} "$(cat ./worktrees/{agent}/run/prompt.md)" Enter
```

Print monitoring instructions for the user:

```
## Parallel Agents Running

Attach to the session:
  tmux attach -t parallel

Monitor progress:
  cat shared/progress/*.json | jq .

Switch between panes:
  Ctrl-b + arrow keys

Kill session when done:
  tmux kill-session -t parallel
```

### Phase 6 -- Merge Strategy

After all agents report "done", provide merge commands:

```bash
# Merge each agent branch with --no-ff to preserve history
git merge --no-ff parallel/{agent-1} -m "Merge {agent-1}: {description}"
git merge --no-ff parallel/{agent-2} -m "Merge {agent-2}: {description}"
git merge --no-ff parallel/{agent-3} -m "Merge {agent-3}: {description}"
```

Conflict resolution guidance:
- If two agents touched the same file despite ownership rules, the
  owning agent's version wins
- For shared config files (package.json, pyproject.toml), merge both
  sets of changes manually
- Run the full test suite after each merge

Cleanup commands:
```bash
# Remove worktrees
git worktree remove ./worktrees/{agent-1}
git worktree remove ./worktrees/{agent-2}
git worktree remove ./worktrees/{agent-3}

# Delete branches
git branch -d parallel/{agent-1}
git branch -d parallel/{agent-2}
git branch -d parallel/{agent-3}

# Remove shared progress
rm -rf ./shared/progress/
```

## Important

- Maximum 3-4 parallel agents. More than 4 has diminishing returns
  and burns credits rapidly.
- Always decompose by domain/module, never by task type.
- Always wait for user approval of the decomposition before creating
  worktrees.
- Each agent MUST have exclusive file ownership. Overlapping writes
  guarantee merge conflicts and wasted work.
- Do not launch agents for tasks that have sequential dependencies.
  If B depends on A's output, A must finish first.
