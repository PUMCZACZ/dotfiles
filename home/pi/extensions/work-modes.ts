import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { isToolCallEventType } from "@earendil-works/pi-coding-agent";

type WorkMode = "normal" | "investigate" | "research";

interface WorkModeState {
  mode: WorkMode;
  baselineTools: string[];
}

const MODE_STATE_TYPE = "work-mode-state";
const INVESTIGATE_TOOLS = ["read", "bash", "grep", "find", "ls"];
const RESEARCH_TOOLS = ["read", "grep", "find", "ls"];
const WRITE_TOOLS = new Set(["edit", "write"]);

const MODE_INSTRUCTIONS: Record<Exclude<WorkMode, "normal">, string> = {
  investigate: `[INVESTIGATE MODE ACTIVE]

Goal: find and explain the bug's root cause before specification or implementation.

Rules:
- Do not edit, write, create, delete, move, or format project files.
- Use read-only code inspection and allowlisted diagnostic shell commands only.
- Trace the real flow through callers, data, runtime boundaries, and outputs. Do not infer behavior from names or UI labels alone.
- Separate confirmed evidence, likely hypotheses, and unknowns.
- Prefer the smallest reproducible check. Do not broaden scope.
- Do not write a specification or implement a fix until the user explicitly changes mode or asks for the next step.

Output:
- Symptom and scope.
- Evidence with relevant file paths and symbols.
- Root cause, including confidence level.
- Minimal fix direction, without changing files.
- Remaining unknowns or verification needed.`,
  research: `[RESEARCH MODE ACTIVE - STRICT READ ONLY]

Goal: locate code and understand current behavior or architecture without changing or executing the project.

Rules:
- Strict read-only mode. Bash, edit, and write are disabled.
- Use only read, grep, find, and ls.
- Locate relevant files, symbols, callers, contracts, and existing patterns.
- Describe what exists now. Do not propose a rewrite unless asked.
- Separate repository facts from assumptions and historical context.
- Do not create specifications, plans, tasks, or files.

Output:
- Direct answer first.
- Relevant paths and symbols.
- Short end-to-end flow.
- Confirmed facts, assumptions, and open questions.`,
};

const BLOCKED_INVESTIGATE_PATTERNS = [
  /(^|\s|[;&|])rm\s/i,
  /(^|\s|[;&|])rmdir\s/i,
  /(^|\s|[;&|])mv\s/i,
  /(^|\s|[;&|])cp\s/i,
  /(^|\s|[;&|])mkdir\s/i,
  /(^|\s|[;&|])touch\s/i,
  /(^|\s|[;&|])chmod\s/i,
  /(^|\s|[;&|])chown\s/i,
  /(^|\s|[;&|])ln\s/i,
  /(^|\s|[;&|])tee\s/i,
  /(^|\s|[;&|])truncate\s/i,
  /(^|\s|[;&|])dd\s/i,
  /(^|\s|[;&|])sudo\s/i,
  /(^|\s|[;&|])su\s/i,
  /(^|\s|[;&|])(kill|pkill|killall)\s/i,
  /(^|[^<])>(?!\s*\/dev\/null)/,
  />>/,
  /\$\(/,
  /`/,
  /\bfind\b[^\n]*(?:-delete|-exec|-execdir|-ok|-fprint|-fprintf)\b/i,
  /\bgit\s+(?:-C\s+\S+\s+)?(?:add|commit|push|pull|fetch|merge|rebase|reset|checkout|switch|restore|stash|cherry-pick|revert|tag|init|clone|clean|worktree)\b/i,
  /\bgit\s+(?:-C\s+\S+\s+)?branch\s+(?:-[dDmM]|--delete|--move)\b/i,
  /\b(?:npm|pnpm|yarn)\s+(?:install|uninstall|add|remove|update|upgrade|ci|link|publish)\b/i,
  /\bcomposer\s+(?:install|update|remove|require)\b/i,
  /\bpip\w*\s+(?:install|uninstall)\b/i,
  /\bbrew\s+(?:install|uninstall|upgrade|update)\b/i,
  /\bdocker\s+(?:run|exec|start|stop|restart|rm|rmi|build|pull|push|create|compose\s+(?:up|down|run|exec|build|pull|push|start|stop|restart|rm))\b/i,
  /\bkubectl\s+(?:apply|create|delete|edit|exec|patch|replace|rollout|scale|set)\b/i,
  /\bcurl\b[^\n]*(?:--data(?:-\w+)?|-d\s|--form|-F\s|--upload-file|-T\s|--output|-o\s|--remote-name|-O(?:\s|$)|-X\s*(?:POST|PUT|PATCH|DELETE))\b/i,
];

const SAFE_INVESTIGATE_SEGMENTS = [
  /^\s*(?:cat|head|tail|less|more|grep|rg|find|fd|ls|eza|tree|pwd|wc|sort|uniq|diff|file|stat|du|df|jq|yq|bat|sed\s+-n|printf|echo|which|whereis|type|env|printenv|uname|whoami|id|date|uptime|ps|lsof)\b/i,
  /^\s*git\s+(?:-C\s+\S+\s+)?(?:status|log|diff|show|blame|grep|rev-parse|ls-files|ls-tree|remote\s+(?:-v|get-url)|config\s+(?:--get|--get-all|--list)|branch\s+(?:--show-current|--list|-a|-r|-v|-vv))\b/i,
  /^\s*(?:npm|pnpm|yarn)\s+(?:test|run\s+(?:test|lint|typecheck|check)|list|ls|view|info|why|audit|outdated)\b/i,
  /^\s*composer\s+(?:show|outdated|audit|validate)\b/i,
  /^\s*(?:php\s+-l|php\s+artisan\s+test|\.?\/?vendor\/bin\/(?:phpunit|pest))\b/i,
  /^\s*dotnet\s+(?:test|build|format\s+--verify-no-changes|list|--info|--version)\b/i,
  /^\s*(?:node|python3?|php|ruby|go|rustc|cargo)\s+--version\b/i,
  /^\s*docker\s+(?:ps|logs|inspect|stats|top|images|version|info)\b/i,
  /^\s*docker\s+compose\s+(?:ps|logs|config|images|top|version)\b/i,
  /^\s*kubectl\s+(?:get|describe|logs|explain|top|version|cluster-info|config\s+current-context)\b/i,
  /^\s*gh\s+(?:status|pr\s+(?:view|diff|list|checks)|issue\s+(?:view|list)|repo\s+view|run\s+(?:view|list))\b/i,
  /^\s*curl\s+(?:-[A-Za-z]+\s+)*https?:\/\//i,
];

function isWorkMode(value: string): value is WorkMode {
  return value === "normal" || value === "investigate" || value === "research";
}

function unique(values: string[]): string[] {
  return [...new Set(values)];
}

function splitShellCommand(command: string): string[] {
  return command
    .split(/\s*(?:&&|\|\||[;|\n])\s*/)
    .map((segment) => segment.trim())
    .filter(Boolean);
}

function isAllowedInvestigateCommand(command: string): boolean {
  if (!command.trim()) return false;
  if (BLOCKED_INVESTIGATE_PATTERNS.some((pattern) => pattern.test(command))) return false;

  const segments = splitShellCommand(command);
  return segments.length > 0 && segments.every((segment) => SAFE_INVESTIGATE_SEGMENTS.some((pattern) => pattern.test(segment)));
}

export default function workModesExtension(pi: ExtensionAPI): void {
  let activeMode: WorkMode = "normal";
  let baselineTools: string[] = [];

  pi.registerFlag("work-mode", {
    description: "Start in work mode: normal, investigate, or research",
    type: "string",
  });

  function availableTools(names: string[]): string[] {
    const available = new Set(pi.getAllTools().map((tool) => tool.name));
    return unique(names).filter((name) => available.has(name));
  }

  function toolsForMode(mode: WorkMode): string[] {
    if (mode === "normal") return availableTools(baselineTools);
    return availableTools(mode === "investigate" ? INVESTIGATE_TOOLS : RESEARCH_TOOLS);
  }

  function updateStatus(ctx: ExtensionContext): void {
    if (activeMode === "normal") {
      ctx.ui.setStatus("work-mode", undefined);
      return;
    }

    const label = activeMode === "investigate" ? "🔎 investigate" : "📚 research:ro";
    const color = activeMode === "investigate" ? "warning" : "accent";
    ctx.ui.setStatus("work-mode", ctx.ui.theme.fg(color, label));
  }

  function persistState(): void {
    pi.appendEntry<WorkModeState>(MODE_STATE_TYPE, {
      mode: activeMode,
      baselineTools: [...baselineTools],
    });
  }

  function applyMode(mode: WorkMode, ctx: ExtensionContext, persist = true): void {
    if (activeMode === "normal" && mode !== "normal") {
      baselineTools = pi.getActiveTools();
    }

    activeMode = mode;
    pi.setActiveTools(toolsForMode(mode));
    updateStatus(ctx);

    if (persist) persistState();

    const message =
      mode === "normal"
        ? "Tryb normalny. Przywrócono poprzednie narzędzia."
        : mode === "investigate"
          ? "Tryb investigate. Zmiany plików zablokowane; dostępne są bezpieczne komendy diagnostyczne."
          : "Tryb research. Ścisły read-only: tylko read, grep, find i ls.";
    ctx.ui.notify(message, "info");
  }

  function restoreState(ctx: ExtensionContext): void {
    const entry = ctx.sessionManager
      .getBranch()
      .filter((item) => item.type === "custom" && item.customType === MODE_STATE_TYPE)
      .pop();

    if (entry?.type === "custom") {
      const state = entry.data as WorkModeState | undefined;
      if (state && isWorkMode(state.mode)) {
        baselineTools = availableTools(state.baselineTools ?? baselineTools);
        activeMode = state.mode;
        pi.setActiveTools(toolsForMode(activeMode));
        updateStatus(ctx);
        return;
      }
    }

    activeMode = "normal";
    pi.setActiveTools(availableTools(baselineTools));
    updateStatus(ctx);
  }

  async function selectMode(ctx: ExtensionContext): Promise<void> {
    if (!ctx.hasUI) {
      ctx.ui.notify("Użycie: /mode normal|investigate|research", "error");
      return;
    }

    const labels = [
      "investigate — diagnoza bez zmian plików",
      "research — ścisły read-only bez bash",
      "normal — przywróć pełny dostęp",
    ];
    const selected = await ctx.ui.select("Wybierz tryb pracy", labels);
    if (!selected) return;
    applyMode(selected.split(" ", 1)[0] as WorkMode, ctx);
  }

  pi.registerCommand("mode", {
    description: "Switch work mode: normal, investigate, or research",
    handler: async (args, ctx) => {
      const requested = args.trim().toLowerCase();
      if (!requested) {
        await selectMode(ctx);
        return;
      }
      if (!isWorkMode(requested)) {
        ctx.ui.notify(`Nieznany tryb "${requested}". Dostępne: normal, investigate, research.`, "error");
        return;
      }
      applyMode(requested, ctx);
    },
  });

  pi.registerCommand("investigate", {
    description: "Enable root-cause investigation without file changes",
    handler: async (_args, ctx) => applyMode("investigate", ctx),
  });

  pi.registerCommand("research", {
    description: "Enable strict read-only codebase research",
    handler: async (_args, ctx) => applyMode("research", ctx),
  });

  pi.on("tool_call", async (event) => {
    if (activeMode === "normal") return;

    if (WRITE_TOOLS.has(event.toolName)) {
      return {
        block: true,
        reason: `Tryb ${activeMode}: narzędzie ${event.toolName} jest zablokowane. Użyj /mode normal, aby zezwolić na zmiany.`,
      };
    }

    if (activeMode === "research" && event.toolName === "bash") {
      return {
        block: true,
        reason: "Tryb research jest ścisłym read-only bez bash. Użyj /mode investigate dla diagnostyki lub /mode normal dla pełnego dostępu.",
      };
    }

    if (activeMode === "investigate" && isToolCallEventType("bash", event)) {
      if (!isAllowedInvestigateCommand(event.input.command)) {
        return {
          block: true,
          reason: `Tryb investigate: komenda nie jest na liście bezpiecznych komend diagnostycznych. Użyj /mode normal, jeśli świadomie chcesz ją wykonać.\nKomenda: ${event.input.command}`,
        };
      }
    }
  });

  pi.on("before_agent_start", async (event) => {
    if (activeMode === "normal") return;
    return {
      systemPrompt: `${event.systemPrompt}\n\n${MODE_INSTRUCTIONS[activeMode]}`,
    };
  });

  pi.on("session_start", async (_event, ctx) => {
    baselineTools = pi.getActiveTools();
    restoreState(ctx);

    const requested = pi.getFlag("work-mode");
    if (typeof requested === "string" && requested) {
      if (isWorkMode(requested)) {
        applyMode(requested, ctx);
      } else {
        ctx.ui.notify(`Nieznany --work-mode "${requested}". Dostępne: normal, investigate, research.`, "warning");
      }
    }
  });

  pi.on("session_tree", async (_event, ctx) => {
    restoreState(ctx);
  });
}
