import { execa } from "execa";
import { mkdtemp, readFile, rm } from "fs/promises";
import { join } from "path";
import { tmpdir } from "os";
import type { DelegateResult } from "../schema.js";
import { toFailureResult } from "./utils.js";

export const PROVIDER_NAME = "codex";

export async function runProvider(prompt: string, model?: string): Promise<DelegateResult> {
  const tmpDir = await mkdtemp(join(tmpdir(), "agent-router-"));
  const outFile = join(tmpDir, "output.txt");
  try {
    const { OPENAI_API_KEY: _omit, ...env } = process.env;
    const args = ["exec", "--output-last-message", outFile, "--ephemeral"];
    if (model) args.push("--model", model);
    args.push(prompt);
    const result = await execa(
      "codex",
      args,
      { env, extendEnv: false, stdin: "ignore" }
    );
    const stdout = await readFile(outFile, "utf-8").catch(() => result.stdout);
    return {
      ok: true,
      provider: PROVIDER_NAME,
      stdout: stdout.trim(),
      stderr: result.stderr,
      exitCode: result.exitCode ?? 0,
    };
  } catch (err) {
    return toFailureResult(PROVIDER_NAME, err);
  } finally {
    await rm(tmpDir, { recursive: true }).catch(() => {});
  }
}
