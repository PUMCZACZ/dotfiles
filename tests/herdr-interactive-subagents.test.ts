import { test } from "node:test";
import { execFileSync } from "node:child_process";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  isMuxAvailable, shellEscape, createSurface, createSurfaceSplit, sendLongCommand,
  sendCommand, readScreen, pollForExit, closeSurface,
} from "../packages/agents/interactive-subagents/herdr.ts";

test("Herdr is required and shell arguments are escaped", () => {
  assert.equal(shellEscape("a'b"), "'a'\\''b'");
  assert.equal(isMuxAvailable(), process.env.HERDR_ENV === "1" && !!process.env.HERDR_PANE_ID &&
    !!process.env.HERDR_SOCKET_PATH && existsSync(process.env.HERDR_SOCKET_PATH));
  assert.throws(() => createSurfaceSplit("ignored", "left"), /cannot split left/);
});

test("real Herdr pane: run, read, detect exit, close without moving focus", { skip: process.env.HERDR_LIVE_TEST !== "1" }, async () => {
  assert.equal(isMuxAvailable(), true);
  const tmp = mkdtempSync(join(tmpdir(), "pi-herdr-test-"));
  const parent = process.env.HERDR_PANE_ID!;
  const focusedBefore = JSON.parse(execFileSync("herdr", ["pane", "get", parent], { encoding: "utf8" })).result.pane.focused;
  const pane = createSurface("adapter-test");
  try {
    assert.match(pane, /^w[^:]+:p/);
    assert.equal(JSON.parse(execFileSync("herdr", ["pane", "get", parent], { encoding: "utf8" })).result.pane.focused, focusedBefore);
    const marker = `SENTINEL_${Date.now()}`;
    const script = join(tmp, "run.sh");
    sendLongCommand(pane, `printf '%s\\n' ${shellEscape(marker)}; echo __SUBAGENT_DONE_0__`, { scriptPath: script });
    const exit = await pollForExit(pane, AbortSignal.timeout(15_000), { interval: 200 });
    assert.deepEqual(exit, { reason: "sentinel", exitCode: 0 });
    assert.match(readScreen(pane), new RegExp(marker));
    sendCommand(pane, "echo herdr-shell-command-ok");
    await new Promise((r) => setTimeout(r, 500));
    assert.match(readScreen(pane), /herdr-shell-command-ok/);
  } finally {
    closeSurface(pane);
    rmSync(tmp, { recursive: true, force: true });
  }
});
