import { z } from "zod";

export const DelegateInputSchema = z.object({
  prompt: z.string().min(1, "prompt must not be empty"),
  json: z.boolean().default(false),
});

export type DelegateInput = z.infer<typeof DelegateInputSchema>;

export type DelegateResult = {
  ok: boolean;
  provider: string;
  stdout: string;
  stderr: string;
  exitCode: number;
};
