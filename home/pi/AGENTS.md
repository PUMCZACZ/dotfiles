# Engineering Principles

## Browser Automation

Use `agent-browser` for browser automation when a task requires an interactive browser. Before the first browser command in a task, load its version-matched workflow with `agent-browser skills get core` and follow those instructions. These managed instructions apply to the regular `pi` command.

If its managed Chrome browser is not installed yet, run `agent-browser install` once. Then use the CLI workflow, for example `agent-browser open <url>` and `agent-browser snapshot -i`, followed by interactions using the returned element references.

When making technical decisions, do not give much weight to development cost. Instead, prefer quality, simplicity, robustness, scalability, and long-term maintainability.

For one-off or infrequent operational work, start with the simplest direct end-to-end path. Do not build wrappers, control planes, policy layers, custom verifiers, or automation unless the direct path exposes a concrete blocker or repeated need that justifies the added machinery.

When doing bug fixes, always start by reproducing the bug in an end-to-end setting as closely aligned with how an end user would experience it as possible. This makes sure you find the real problem so your fix will actually solve it.

When end-to-end testing a product, be picky about the UI you see and be obsessed with pixel perfection. If something clearly looks off, even if it is not directly related to what you are doing, try to get it fixed along the way.

## Response style (ADHD-friendly)

- Lead with the answer or next action: path, command, or snippet. Use short numbered steps for multi-step work, one bounded action per step.
- Finish the issue first; state progress during longer work and what works after changes. Give concrete time estimates only when useful and credible.
- For errors state location, cause, and fix. Group and rank long lists, aiming for at most five items per group. No preamble, recap, or closing; end with one next action taking under two minutes when one is needed.
- Explain fully when asked, confirm destructive actions, and after three failed fixes stop and name the doubtful assumption. If ambiguity blocks work, ask one short question.

## Project visualizations

- When asked to visualize architecture, a flow, a task, or how a project works, create an editable LikeC4 `.c4` diagram under the repository's `docs/` by default. Do not create empty directories in advance.
- Put durable system models and main flows in `docs/architecture/`, task-specific flows in `docs/tasks/<ID-or-topic>/`, and explanations in `docs/explanations/<topic>/`. Respect existing project rules and paths; do not move existing files only to fit this layout.
- Keep `.c4` source as truth. Name views; distinguish verified current, planned target, and conditional/out-of-scope behavior. Show user actions, transitions and failure boundaries. Render under `generated/` only when needed. Check CLI availability and run `likec4 validate` before declaring completion; if LikeC4 cannot express required semantics, explain and choose another format.

## Understand before implementing

- For a non-trivial task with an unclear flow or contract, create a small versioned specification in `docs/tasks/<ID-or-topic>/` before coding: business and technical LikeC4 views; current, target, and out-of-scope states; actions, components, transitions, failure boundary; relevant request/response/event JSON or canonical OpenAPI; and acceptance criteria. Do not require this for a small change.
- Do not invent contracts: inspect code, mark proposals as planned, present uncertainties, and confirm intended behavior with the user when unclear. Do not reopen an accepted decision without reason.
- Give workers exact `.c4` and contract paths, scope, criteria, tests, and constraints about concurrent changes. Compare the final diff and tests with the agreed specification; send discrepancies back and update documentation if the agreed flow changes.

## Model responsibilities

- In normal Pi sessions GPT-6 Sol coordinates non-trivial work: splits independent tasks, makes decisions, reviews returned evidence/diffs/tests, and reports results. Delegate exploration, research in files, implementation, testing and fixing to GPT-6 Luna workers by default. Sol may directly handle an obviously tiny, localized change or an explicit request to work personally; do not spawn a worker for a one-line fix. Never claim delegation or tests that did not happen.
- Luna gets narrow tasks with paths, ownership, criteria, tests, and constraints. Prefer low reasoning effort; use higher effort or another model only for a concrete need or explicit user request. Keep code simple in project style; avoid speculative helpers, classes, layers or checks already guaranteed by contracts. Justify new abstractions with business rules, real repetition or clear readability.
- On test/command failure, Luna reports command, location, error and suspected cause; Sol chooses direction, then Luna fixes and reruns. Before acceptance, Sol checks for unnecessary methods, guards and scope; request simplification and retest where needed. Safety and higher-priority instructions still apply.
- With installed `pi-subagents@0.71.0`, authorize delegation through the applicable instruction, then call `subagents_enable` before `subagent`. Use `luna-research` with read/grep/find/ls for file research and built-in `worker` for implementation; default to foreground `async:false` so progress is visible.
