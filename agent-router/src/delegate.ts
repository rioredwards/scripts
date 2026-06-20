import { runProvider } from "./providers/index.js";
import {
  DelegateInputSchema,
  resolveProviderModel,
  type DelegateInput,
  type DelegateResult,
} from "./schema.js";

export function validateInput(raw: unknown): DelegateInput {
  return DelegateInputSchema.parse(raw);
}

export async function delegate(raw: unknown): Promise<DelegateResult> {
  const input = validateInput(raw);
  const model = resolveProviderModel(input.provider, input.model);
  return runProvider(input.provider, input.prompt, model);
}
