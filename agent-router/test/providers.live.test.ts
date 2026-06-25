import { describe, expect, it } from "vitest";
import { runProvider } from "../src/providers/index.js";
import {
  DEFAULT_PROVIDER_MODELS,
  PROVIDER_MODELS,
  PROVIDERS,
  type ProviderName,
} from "../src/schema.js";

// Live provider smoke tests. These spawn the REAL agent binaries and spend
// plan credits, so they are OFF by default and skipped in `pnpm test`.
//
// Enable with the RUN_LIVE_PROVIDERS env flag:
//   RUN_LIVE_PROVIDERS=1     -> default model per provider (cheap: one call each)
//   RUN_LIVE_PROVIDERS=all   -> every model in PROVIDER_MODELS (full matrix)
//
// Scope to a single provider with LIVE_PROVIDER=<name>, e.g.
//   RUN_LIVE_PROVIDERS=1 LIVE_PROVIDER=antigravity pnpm test:live
//
// Each call only asks for "pong", so token use stays minimal even on the
// fancier models in the `all` matrix.

const liveMode = process.env.RUN_LIVE_PROVIDERS;
const onlyProvider = process.env.LIVE_PROVIDER as ProviderName | undefined;

const PROMPT = "Reply with exactly one word and nothing else: pong";
const TIMEOUT_MS = 180_000;

function modelsFor(provider: ProviderName): string[] {
  if (liveMode === "all") return PROVIDER_MODELS[provider];
  return [DEFAULT_PROVIDER_MODELS[provider]];
}

const providers: ProviderName[] = onlyProvider ? [onlyProvider] : [...PROVIDERS];

describe.skipIf(!liveMode)("live provider smoke", () => {
  for (const provider of providers) {
    for (const model of modelsFor(provider)) {
      it(
        `${provider} (${model}) replies pong`,
        async () => {
          const result = await runProvider(provider, PROMPT, model);
          expect(result.ok, result.stderr).toBe(true);
          expect(result.stdout.toLowerCase()).toContain("pong");
        },
        TIMEOUT_MS,
      );
    }
  }
});
