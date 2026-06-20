import { execa } from "execa";
import type { DelegateResult } from "../schema.js";
import { toFailureResult } from "./utils.js";

export const PROVIDER_NAME = "opencode";

export async function runProvider(prompt: string, model?: string): Promise<DelegateResult> {
  try {
    const args = ["run", prompt, "--format", "json"];
    if (model) args.push("--model", model);
    const result = await execa("opencode", args, { stdin: "ignore" });
    const text = extractText(result.stdout);
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

function extractText(raw: string): string {
  return raw
    .split("\n")
    .flatMap((line) => {
      if (!line.trim()) return [];
      try {
        const event = JSON.parse(line) as { type?: string; part?: { text?: string } };
        if (event.type === "text" && event.part?.text) return [event.part.text];
      } catch {
        // non-JSON line, skip
      }
      return [];
    })
    .join("");
}
