import { execa } from "execa";
import type { DelegateResult } from "../schema.js";
import { toFailureResult } from "./utils.js";

export const PROVIDER_NAME = "antigravity";

export async function runProvider(prompt: string, model?: string): Promise<DelegateResult> {
  try {
    const args: string[] = [];
    if (model) args.push("--model", model);
    args.push("-p", prompt);
    // agy blocks reading stdin in print mode if stdin is an open pipe (execa's
    // default), so ignore it. The prompt is passed as the -p flag value.
    const result = await execa("agy", args, { stdin: "ignore" });
    const stdout = result.stdout.trim();
    if (!stdout) {
      return {
        ok: false,
        provider: PROVIDER_NAME,
        stdout: "",
        stderr: result.stderr || "agy returned empty output",
        exitCode: result.exitCode ?? 0,
      };
    }
    return {
      ok: true,
      provider: PROVIDER_NAME,
      stdout,
      stderr: result.stderr,
      exitCode: result.exitCode ?? 0,
    };
  } catch (err) {
    return toFailureResult(PROVIDER_NAME, err);
  }
}
