import type { DelegateResult } from "../schema.js";

export function toFailureResult(provider: string, err: unknown): DelegateResult {
  const e = err as { stdout?: string; stderr?: string; exitCode?: number };
  return {
    ok: false,
    provider,
    stdout: e.stdout ?? "",
    stderr: e.stderr ?? String(err),
    exitCode: e.exitCode ?? 1,
  };
}
