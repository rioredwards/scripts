import { z } from "zod";

export const DelegateInputSchema = z.object({
  prompt: z.string().min(1, "prompt must not be empty"),
  json: z.boolean().default(false),
  provider: z.enum(["claude", "codex"]).default("claude"),
});

export type DelegateInput = z.infer<typeof DelegateInputSchema>;
export type ProviderName = DelegateInput["provider"];

export type DelegateResult = {
  ok: boolean;
  provider: string;
  stdout: string;
  stderr: string;
  exitCode: number;
};
