import { runProvider as runClaude } from "./claude.js";
import { runProvider as runCodex } from "./codex.js";
import { runProvider as runAntigravity } from "./antigravity.js";
import { runProvider as runOpencode } from "./opencode.js";
import type { DelegateResult, ProviderName } from "../schema.js";

export type { ProviderName };

export function runProvider(provider: ProviderName, prompt: string, model?: string): Promise<DelegateResult> {
  switch (provider) {
    case "codex":
      return runCodex(prompt, model);
    case "claude":
      return runClaude(prompt, model);
    case "antigravity":
      return runAntigravity(prompt, model);
    case "opencode":
      return runOpencode(prompt, model);
  }
}
