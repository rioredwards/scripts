import { DelegateInputSchema, type DelegateInput, type DelegateResult } from "./schema.js";
import { runProvider } from "./providers/index.js";

export function validateInput(raw: unknown): DelegateInput {
  return DelegateInputSchema.parse(raw);
}

export async function delegate(raw: unknown): Promise<DelegateResult> {
  const input = validateInput(raw);
  return runProvider(input.provider, input.prompt, input.model);
}
