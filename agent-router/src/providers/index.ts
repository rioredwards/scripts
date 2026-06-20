import { runProvider as runClaude } from "./claude.js";
import { runProvider as runCodex } from "./codex.js";
import type { DelegateResult, ProviderName } from "../schema.js";

export type { ProviderName };

export function runProvider(provider: ProviderName, prompt: string, model?: string): Promise<DelegateResult> {
  switch (provider) {
    case "codex":
      return runCodex(prompt, model);
    case "claude":
      return runClaude(prompt, model);
  }
}
