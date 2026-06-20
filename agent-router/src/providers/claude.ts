import { execa } from "execa";
import type { DelegateResult } from "../schema.js";
import { toFailureResult } from "./utils.js";

export const PROVIDER_NAME = "claude";

export async function runProvider(prompt: string, model?: string): Promise<DelegateResult> {
  try {
    const { ANTHROPIC_API_KEY: _omit, ...env } = process.env;
    const args = ["--print"];
    if (model) args.push("--model", model);
    args.push(prompt);
    const result = await execa("claude", args, { env, extendEnv: false });
    return {
      ok: true,
      provider: PROVIDER_NAME,
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode ?? 0,
    };
  } catch (err) {
    return toFailureResult(PROVIDER_NAME, err);
  }
}
