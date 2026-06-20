import { Command } from "commander";
import { delegate } from "./delegate.js";
import { ZodError } from "zod";

const program = new Command();

program
  .name("agent-router")
  .description("Route and delegate tasks to agent CLIs")
  .version("0.1.0");

program.showHelpAfterError();

program
  .command("delegate")
  .description("Delegate a task to the configured provider")
  .requiredOption("--prompt <text>", "task prompt to send to the provider")
  .option("--provider <name>", "provider to use: claude, codex")
  .option("--model <name>", "model to use for the selected provider")
  .option("--json", "output result as JSON", false)
  .action(async (opts: { prompt: string; provider?: string; model?: string; json: boolean }) => {
    const useJson = opts.json;
    try {
      const result = await delegate({
        prompt: opts.prompt,
        provider: opts.provider,
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
      process.stderr.write(`Unexpected error: ${String(err)}\n`);
      process.exit(1);
    }
  });

// pnpm passes `--` as argv[2] when using `pnpm dev -- <args>`; strip it
if (process.argv[2] === "--") process.argv.splice(2, 1);

await program.parseAsync();
