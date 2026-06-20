import { execa } from "execa";
import { homedir } from "node:os";
import path from "node:path";
import type { DelegateResult } from "../schema.js";
import { toFailureResult } from "./utils.js";

export const PROVIDER_NAME = "cursor";

// Reuse the battle-tested shell wrapper instead of reimplementing the finnicky
// cursor-agent invocation (stream-json + --trust + watchdog timeout + retry).
// The script lives in the cursor-delegate skill; honor LNSKILL_ROOT like the
// skills do, fall back to ~/dev/agent-skills.
function delegateScriptPath(): string {
  const root = process.env.LNSKILL_ROOT || path.join(homedir(), "dev", "agent-skills");
  return path.join(root, "general", "cursor-delegate", "cursor-delegate.sh");
}

// cursor-delegate.sh has no read-only model flag of its own; it reads CURSOR_MODEL.
// Default mode is `ask` (read-only, the most reliable cursor path). Override the
// mode with CURSOR_MODE=plan|ask|edit; `edit` lets cursor write files.
export async function runProvider(prompt: string, model?: string): Promise<DelegateResult> {
  try {
    const mode = process.env.CURSOR_MODE || "ask";
    const env = model ? { ...process.env, CURSOR_MODEL: model } : process.env;
    const result = await execa("bash", [delegateScriptPath(), mode, prompt], {
      env,
      stdin: "ignore",
    });
    const text = extractResult(result.stdout);
    if (!text) {
      return {
        ok: false,
        provider: PROVIDER_NAME,
        stdout: "",
        stderr: result.stderr || "cursor returned no [cursor:result] block",
        exitCode: result.exitCode ?? 0,
      };
    }
    return {
      ok: true,
      provider: PROVIDER_NAME,
      stdout: text,
      stderr: result.stderr,
      exitCode: result.exitCode ?? 0,
    };
  } catch (err) {
    return toFailureResult(PROVIDER_NAME, err);
  }
}

// The script prints filtered heartbeat lines; the answer is the block between
// `[cursor:result]` and the trailing `[cursor:done]` marker (or EOF).
function extractResult(raw: string): string {
  const lines = raw.split("\n");
  const start = lines.findIndex((line) => line.startsWith("[cursor:result]"));
  if (start === -1) return "";
  const body: string[] = [];
  for (const line of lines.slice(start + 1)) {
    if (line.startsWith("[cursor:done]")) break;
    body.push(line);
  }
  return body.join("\n").trim();
}
