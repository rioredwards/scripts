import { execa } from "execa";
import type { DelegateResult } from "./schema.js";

export const PROVIDER_NAME = "claude";

export async function runProvider(prompt: string): Promise<DelegateResult> {
  try {
    const { ANTHROPIC_API_KEY: _omit, ...env } = process.env;
    const result = await execa("claude", ["--print", prompt], { env, extendEnv: false });
    return {
      ok: true,
      provider: PROVIDER_NAME,
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode ?? 0,
    };
  } catch (err: unknown) {
    const e = err as { stdout?: string; stderr?: string; exitCode?: number };
    return {
      ok: false,
      provider: PROVIDER_NAME,
      stdout: e.stdout ?? "",
      stderr: e.stderr ?? String(err),
      exitCode: e.exitCode ?? 1,
    };
  }
}
