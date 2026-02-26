# Agent Skills

A collection of skills for Claude Code and other AI coding agents, compatible with the [skills.sh](https://skills.sh) ecosystem.

## Install all skills

```bash
npx skills add Jay-523/agent-skills
```

## Install a single skill

```bash
npx skills add https://github.com/Jay-523/agent-skills/tree/main/skills/<skill-name>
```

## Available skills

| Skill | Command | Description |
|-------|---------|-------------|
| parallel-research | `/parallel-research` | Decompose a research question into MECE domains and run parallel Claude agents via tmux |
| parallel | `/parallel` | Split implementation tasks into independent workstreams running as parallel agents in git worktrees |
| insights | `/insights` | Extract coding patterns and preferences from session transcripts for CLAUDE.md |
| test | `/test` | Full TDD red-green-refactor cycle with automatic framework detection |
| socratic_mentor | `/socratic_mentor` | Guided learning through Socratic questioning -- teaches through discovery, not answers |

## Example: install just the parallel-research skill

```bash
npx skills add https://github.com/Jay-523/agent-skills/tree/main/skills/parallel-research
```
