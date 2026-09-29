import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const COMPACTION_THRESHOLD_PERCENT = 80;

const HANDOFF_SUMMARY_INSTRUCTIONS = `Create a detailed, standalone handoff checkpoint for the next model invocation. The next assistant must be able to continue correctly without access to the summarized messages.

Prioritize completeness and operational usefulness over brevity. In addition to the standard summary sections, preserve:
- the user's current goal, exact request, acceptance criteria, constraints, and stated preferences;
- completed, in-progress, pending, and explicitly rejected work, with enough chronology to explain the current state;
- decisions and their rationale, assumptions, unresolved questions, blockers, and risks;
- exact file paths, symbols, commands, important values, URLs, IDs, error messages, and other details that would be expensive or impossible to rediscover;
- every file changed and the material change made, plus important files only inspected and what was learned from them;
- tool calls and command/test results that affected the work, clearly distinguishing successes, failures, and unverified claims;
- the last action taken and an ordered, concrete continuation plan.

Do not use vague references such as "the code above" or "as discussed earlier". Do not claim that work or verification happened unless the conversation records it. Preserve all still-relevant information from any previous summary, especially unresolved items.`;

export default function autoCompactionExtension(pi: ExtensionAPI): void {
  let compactionInProgress = false;

  function notify(ctx: ExtensionContext, message: string, level: "info" | "warning"): void {
    if (ctx.hasUI) ctx.ui.notify(message, level);
  }

  pi.on("agent_settled", async (_event, ctx) => {
    if (compactionInProgress) return;

    const percent = ctx.getContextUsage()?.percent;
    if (percent === null || percent === undefined || percent < COMPACTION_THRESHOLD_PERCENT) return;

    compactionInProgress = true;
    notify(ctx, `Context is ${Math.round(percent)}% full; creating a detailed handoff summary`, "info");

    ctx.compact({
      customInstructions: HANDOFF_SUMMARY_INSTRUCTIONS,
      onComplete: () => {
        compactionInProgress = false;
        notify(ctx, "Automatic compaction completed with a detailed handoff summary", "info");
      },
      onError: (error) => {
        compactionInProgress = false;
        notify(ctx, `Automatic compaction failed: ${error.message}`, "warning");
      },
    });
  });
}
