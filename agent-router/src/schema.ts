import { z } from "zod";

export const DelegateInputSchema = z.object({
  prompt: z.string().min(1, "prompt must not be empty"),
  json: z.boolean().default(false),
  provider: z.enum(["claude", "codex", "antigravity", "opencode"]).default("claude"),
  model: z.string().min(1, "model must not be empty").optional(),
});

export type DelegateInput = z.infer<typeof DelegateInputSchema>;
export type ProviderName = DelegateInput["provider"];

export const PROVIDERS = DelegateInputSchema.shape.provider.removeDefault().options;

export const PROVIDER_MODELS: Record<ProviderName, string[]> = {
  claude: ["opus", "sonnet", "haiku"],
  codex: ["gpt-5.5", "gpt-5.4", "gpt-5.4-mini"],
  antigravity: [
    "gemini 3.5 Flash (High)",
    "gemini 3.1 Pro (High)",
    "Claude Sonnet 4.6 (Thinking)",
    "Claude Opus 4.6 (Thinking)",
    "GPT-OSS 120B (Medium)",
  ],
  opencode: [
    "openai/gpt-5.5",
    "openai/gpt-5.4",
    "openai/gpt-5.4-mini",
    "deepseek/deepseek-v4-pro",
    "deepseek/deepseek-v4-flash",
  ],
};

export const DEFAULT_PROVIDER_MODELS: Record<ProviderName, string> = {
  claude: "sonnet",
  codex: "gpt-5.4",
  antigravity: "gemini 3.1 Pro (High)",
  opencode: "deepseek/deepseek-v4-pro",
};

export function resolveProviderModel(provider: ProviderName, model?: string): string {
  return model ?? DEFAULT_PROVIDER_MODELS[provider];
}

export type DelegateResult = {
  ok: boolean;
  provider: string;
  stdout: string;
  stderr: string;
  exitCode: number;
};
