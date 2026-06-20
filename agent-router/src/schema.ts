import { z } from "zod";

export const DelegateInputSchema = z.object({
  prompt: z.string().min(1, "prompt must not be empty"),
  json: z.boolean().default(false),
  provider: z.enum(["claude", "codex", "antigravity", "opencode", "cursor"]).default("claude"),
  model: z.string().min(1, "model must not be empty").optional(),
});

export type DelegateInput = z.infer<typeof DelegateInputSchema>;
export type ProviderName = DelegateInput["provider"];

export const PROVIDERS = DelegateInputSchema.shape.provider.removeDefault().options;

export const PROVIDER_MODELS: Record<ProviderName, string[]> = {
  claude: ["opus", "sonnet", "haiku"],
  codex: ["gpt-5.5", "gpt-5.4", "gpt-5.4-mini"],
  antigravity: [
    "Gemini 3.5 Flash (High)",
    "Gemini 3.1 Pro (High)",
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
  cursor: [
    "composer-2.5",
    "composer-2.5-fast",
    "auto",
    "gpt-5.2",
    "claude-opus-4-8-thinking-high",
  ],
};

export const DEFAULT_PROVIDER_MODELS: Record<ProviderName, string> = {
  claude: "sonnet",
  codex: "gpt-5.4",
  antigravity: "Gemini 3.1 Pro (High)",
  opencode: "deepseek/deepseek-v4-pro",
  cursor: "composer-2.5",
};

export const PROVIDER_DETAILS: Record<
  ProviderName,
  { binary: string; command: string; note: string }
> = {
  claude: {
    binary: "claude",
    command: "claude --print --model <model> <prompt>",
    note: "Uses Claude Code non-interactive mode; API key env is stripped so OAuth plan credits work.",
  },
  codex: {
    binary: "codex",
    command: "codex exec --output-last-message <tmp> --ephemeral --model <model> <prompt>",
    note: "Writes last message to a temp file, then prints it; API key env is stripped for OAuth.",
  },
  antigravity: {
    binary: "agy",
    command: "agy -p --model <model>",
    note: "Prompt is piped over stdin because positional prompts are misparsed by agy.",
  },
  opencode: {
    binary: "opencode",
    command: "opencode run <prompt> --model <model> --format json",
    note: "Reads JSON event stream and joins text events into final stdout.",
  },
  cursor: {
    binary: "cursor-agent",
    command: "cursor-delegate.sh <mode> <prompt> (CURSOR_MODEL=<model>)",
    note: "Reuses the cursor-delegate skill script (stream-json + --trust + watchdog + retry). Read-only `ask` mode by default; set CURSOR_MODE=plan|ask|edit (edit can write files).",
  },
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
