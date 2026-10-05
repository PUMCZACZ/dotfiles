/* Herdr 0.8.0 terminal surface for pi-interactive-subagents 3.7.2.
 * Pi conversations remain in their own JSONL sessions; Herdr owns only panes.
 */
import { execFile, execFileSync } from "node:child_process";
import { promisify } from "node:util";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";

const execAsync = promisify(execFile);

export function isMuxAvailable(): boolean {
  return process.env.HERDR_ENV === "1" && !!process.env.HERDR_PANE_ID &&
    !!process.env.HERDR_SOCKET_PATH && existsSync(process.env.HERDR_SOCKET_PATH);
}

export function muxSetupHint(): string {
  return "Run pi in a Herdr-managed pane with a running Herdr server.";
}

function requireHerdr(): void {
  if (!isMuxAvailable()) throw new Error(`Herdr is required for interactive subagents. ${muxSetupHint()}`);
}

function cli(args: string[]): string {
  requireHerdr();
  return execFileSync("herdr", args, { encoding: "utf8", timeout: 15_000 });
}

function paneIdFrom(json: string): string {
  const parsed = JSON.parse(json);
  if (parsed.error) throw new Error(parsed.error.message ?? JSON.stringify(parsed.error));
  const id = parsed.result?.pane?.pane_id;
  if (typeof id !== "string" || !id) throw new Error(`Unexpected Herdr split response: ${json}`);
  return id;
}

export function shellEscape(value: string): string {
  return "'" + value.replace(/'/g, "'\\''") + "'";
}

export function createSurface(name: string): string {
  return createSurfaceSplit(name, "right", process.env.HERDR_PANE_ID);
}

export function createSurfaceSplit(
  _name: string,
  direction: "left" | "right" | "up" | "down",
  fromSurface?: string,
): string {
  if (direction !== "right" && direction !== "down") {
    throw new Error(`Herdr 0.8.0 cannot split ${direction}; use right or down.`);
  }
  requireHerdr();
  const source = fromSurface ?? process.env.HERDR_PANE_ID!;
  return paneIdFrom(cli(["pane", "split", source, "--direction", direction, "--cwd", process.cwd(), "--no-focus"]));
}

/** Shell commands and live Pi prompts have different Herdr submission APIs. */
export function sendCommand(surface: string, command: string): void {
  requireHerdr();
  const info = JSON.parse(cli(["pane", "get", surface]));
  if (info.error) throw new Error(info.error.message ?? JSON.stringify(info.error));
  if (info.result?.pane?.agent === "pi") {
    cli(["agent", "prompt", surface, command]);
  } else {
    cli(["pane", "run", surface, command]);
  }
}

export function sendLongCommand(
  surface: string,
  command: string,
  options?: { scriptPath?: string; scriptPreamble?: string },
): string {
  const path = options?.scriptPath ?? join(tmpdir(), "pi-herdr-subagent-scripts", `cmd-${Date.now()}-${Math.random().toString(16).slice(2)}.sh`);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `#!/bin/sh\n${options?.scriptPreamble ?? ""}\n${command}\n`, { mode: 0o700 });
  // Only short script invocation crosses the terminal; no prompt truncation.
  try {
    cli(["pane", "run", surface, `sh ${shellEscape(path)}`]);
  } catch (error) {
    try { closeSurface(surface); } catch { /* pane may already be gone */ }
    throw error;
  }
  return path;
}

export function readScreen(surface: string, lines = 50): string {
  return cli(["pane", "read", surface, "--source", "visible", "--lines", String(Math.max(1, lines))]);
}

export async function readScreenAsync(surface: string, lines = 50): Promise<string> {
  requireHerdr();
  const { stdout } = await execAsync("herdr", ["pane", "read", surface, "--source", "visible", "--lines", String(Math.max(1, lines))], { encoding: "utf8", timeout: 15_000 });
  return stdout;
}

export function closeSurface(surface: string): void {
  cli(["pane", "close", surface]);
}

/** Prevent two Pi processes from appending to the same JSONL after parent restart. */
export function findLiveSessionSurface(sessionFile: string): string | null {
  const result = JSON.parse(cli(["agent", "list"]));
  if (result.error) throw new Error(result.error.message ?? JSON.stringify(result.error));
  const agent = result.result?.agents?.find((a: any) =>
    a.agent === "pi" && a.agent_session?.value === sessionFile && typeof a.pane_id === "string");
  return agent?.pane_id ?? null;
}

export interface PollResult {
  reason: "done" | "sentinel" | "error";
  exitCode: number;
  errorMessage?: string;
}

export async function pollForExit(
  surface: string,
  signal: AbortSignal,
  options: { interval: number; sessionFile?: string; sentinelFile?: string; onTick?: (elapsed: number) => void },
): Promise<PollResult> {
  const started = Date.now();
  for (;;) {
    if (signal.aborted) throw new Error("Aborted while waiting for subagent");
    if (options.sessionFile) {
      const sidecar = `${options.sessionFile}.exit`;
      if (existsSync(sidecar)) {
        try {
          const payload = JSON.parse(readFileSync(sidecar, "utf8"));
          rmSync(sidecar, { force: true });
          if (payload.type === "error") {
            return { reason: "error", exitCode: 1, errorMessage: payload.errorMessage || "Subagent failed" };
          }
          return { reason: "done", exitCode: 0 };
        } catch { /* sidecar may still be in flight */ }
      }
    }
    if (options.sentinelFile && existsSync(options.sentinelFile)) return { reason: "sentinel", exitCode: 0 };
    try {
      const screen = await readScreenAsync(surface, 20);
      const match = screen.match(/__SUBAGENT_DONE_(\d+)__/);
      if (match) return { reason: "sentinel", exitCode: Number(match[1]) };
    } catch (error) {
      // A closed pane must not leave a watcher spinning forever.
      try { cli(["pane", "get", surface]); }
      catch { return { reason: "error", exitCode: 1, errorMessage: `Herdr pane ${surface} disappeared: ${String(error)}` }; }
    }
    options.onTick?.(Math.floor((Date.now() - started) / 1000));
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => { signal.removeEventListener("abort", aborted); resolve(); }, options.interval);
      function aborted() { clearTimeout(timer); reject(new Error("Aborted while waiting for subagent")); }
      signal.addEventListener("abort", aborted, { once: true });
    });
  }
}
