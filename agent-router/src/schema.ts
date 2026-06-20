import { z } from "zod";

export const DelegateInputSchema = z.object({
  prompt: z.string().min(1, "prompt must not be empty"),
  json: z.boolean().default(false),
  provider: z.enum(["claude", "codex", "antigravity"]).default("claude"),
  model: z.string().min(1, "model must not be empty").optional(),
});

export type DelegateInput = z.infer<typeof DelegateInputSchema>;
export type ProviderName = DelegateInput["provider"];

export const PROVIDERS = DelegateInputSchema.shape.provider.removeDefault().options;

export const PROVIDER_MODELS: Record<ProviderName, string[]> = {
  claude: [
    "claude-opus-4-8",
    "claude-sonnet-4-6",
    "claude-haiku-4-5-20251001",
  ],
  codex: [
    "codex-mini-latest",
    "o4-mini",
    "o3",
    "gpt-4.1",
    "gpt-4.1-mini",
  ],
  antigravity: [
    "gemini-2.5-flash",
    "gemini-2.5-pro",
    "claude-sonnet-4-6",
    "claude-opus-4-6",
  ],
};

export type DelegateResult = {
  ok: boolean;
  provider: string;
  stdout: string;
  stderr: string;
  exitCode: number;
};
