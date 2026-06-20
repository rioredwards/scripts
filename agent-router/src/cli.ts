import { Command, Option } from "commander";
import { delegate } from "./delegate.js";
import { PROVIDERS, PROVIDER_MODELS, type ProviderName } from "./schema.js";
import { ZodError } from "zod";

const program = new Command();

type DelegateOptions = {
  prompt?: string;
  provider?: ProviderName;
  model?: string;
  json: boolean;
};

class CliValidationError extends Error {}

function resolvePrompt(argumentPrompt: string | undefined, optionPrompt: string | undefined): string | undefined {
  return optionPrompt ?? argumentPrompt;
}

function validateModel(provider: ProviderName, model: string | undefined): void {
  if (!model) return;

  const models = PROVIDER_MODELS[provider];
  if (!models.includes(model)) {
    throw new CliValidationError(`Unknown model for ${provider}: ${model}. Available: ${models.join(", ")}`);
  }
}

program
  .name("agent-router")
  .description("Route and delegate tasks to agent CLIs")
  .version("0.1.0");

program.showHelpAfterError();

program
  .command("delegate [prompt]")
  .description("Delegate a task to the configured provider")
  .option("--prompt <text>", "task prompt to send to the provider")
  .addOption(new Option("--provider <name>", "provider to use").choices([...PROVIDERS]))
  .option("--model <name>", "model to use for the selected provider")
  .option("--json", "output result as JSON", false)
  .action(async (argumentPrompt: string | undefined, opts: DelegateOptions) => {
    const useJson = opts.json;
    try {
      const provider = opts.provider ?? "claude";
      validateModel(provider, opts.model);

      const result = await delegate({
        prompt: resolvePrompt(argumentPrompt, opts.prompt),
        provider,
        model: opts.model,
        json: useJson,
      });
      if (useJson) {
        process.stdout.write(JSON.stringify(result, null, 2) + "\n");
      } else {
        process.stdout.write(result.stdout + "\n");
      }
      process.exit(result.exitCode);
    } catch (err) {
      if (err instanceof ZodError) {
        const msg = err.errors.map((e) => e.message).join(", ");
        if (useJson) {
          process.stdout.write(JSON.stringify({ ok: false, error: msg }) + "\n");
        } else {
          process.stderr.write(`Validation error: ${msg}\n`);
        }
        process.exit(1);
      }
      if (err instanceof CliValidationError) {
        if (useJson) {
          process.stdout.write(JSON.stringify({ ok: false, error: err.message }) + "\n");
        } else {
          process.stderr.write(`Validation error: ${err.message}\n`);
        }
        process.exit(1);
      }
      process.stderr.write(`Unexpected error: ${String(err)}\n`);
      process.exit(1);
    }
  });

program
  .command("providers")
  .description("List available providers")
  .action(() => {
    PROVIDERS.forEach((p) => process.stdout.write(p + "\n"));
  });

program
  .command("models")
  .description("List known models for a provider")
  .requiredOption("--provider <name>", "provider to list models for")
  .action((opts: { provider: string }) => {
    const models = PROVIDER_MODELS[opts.provider as ProviderName];
    if (!models) {
      process.stderr.write(`Unknown provider: ${opts.provider}. Available: ${PROVIDERS.join(", ")}\n`);
      process.exit(1);
    }
    models.forEach((m) => process.stdout.write(m + "\n"));
  });

// pnpm passes `--` as argv[2] when using `pnpm dev -- <args>`; strip it
if (process.argv[2] === "--") process.argv.splice(2, 1);

await program.parseAsync();
