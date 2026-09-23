# Engineering Principles

## Browser Automation

Use `agent-browser` for browser automation when a task requires an interactive browser. Before the first browser command in a task, load its version-matched workflow with `agent-browser skills get core` and follow those instructions. These managed instructions apply to the regular `pi` command.

If its managed Chrome browser is not installed yet, run `agent-browser install` once. Then use the CLI workflow, for example `agent-browser open <url>` and `agent-browser snapshot -i`, followed by interactions using the returned element references.

When making technical decisions, do not give much weight to development cost. Instead, prefer quality, simplicity, robustness, scalability, and long-term maintainability.

For one-off or infrequent operational work, start with the simplest direct end-to-end path. Do not build wrappers, control planes, policy layers, custom verifiers, or automation unless the direct path exposes a concrete blocker or repeated need that justifies the added machinery.

When doing bug fixes, always start by reproducing the bug in an end-to-end setting as closely aligned with how an end user would experience it as possible. This makes sure you find the real problem so your fix will actually solve it.

When end-to-end testing a product, be picky about the UI you see and be obsessed with pixel perfection. If something clearly looks off, even if it is not directly related to what you are doing, try to get it fixed along the way.
