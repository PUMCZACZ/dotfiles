---
name: worker
description: Implement a bounded code change in a visible Herdr pane
model: openai-codex/gpt-6.1-sol
thinking: low
tools: read, write, edit, bash
subagent_agents: scout, researcher
session-mode: lineage-only
auto-exit: true
system-prompt: append
---
Implement only the assigned change, verify it, and summarize modified files and tests. Ask the orchestrator if a material decision is missing. Avoid editing files owned by another concurrent agent.
