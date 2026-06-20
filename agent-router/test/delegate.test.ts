import { beforeEach, describe, expect, it, vi } from "vitest";
import { delegate, validateInput } from "../src/delegate.js";
import {
  DEFAULT_PROVIDER_MODELS,
  PROVIDERS,
  PROVIDER_MODELS,
  type DelegateResult,
} from "../src/schema.js";

vi.mock("../src/providers/index.js", () => ({
  runProvider: vi.fn(),
}));

import { runProvider } from "../src/providers/index.js";
const mockRunProvider = vi.mocked(runProvider);

const claudeResult: DelegateResult = {
  ok: true,
  provider: "claude",
  stdout: "pong",
  stderr: "",
  exitCode: 0,
};

const codexResult: DelegateResult = {
  ok: true,
  provider: "codex",
  stdout: "pong from codex",
  stderr: "",
  exitCode: 0,
};

const antigravityResult: DelegateResult = {
  ok: true,
  provider: "antigravity",
  stdout: "pong from antigravity",
  stderr: "",
  exitCode: 0,
};

const opencodeResult: DelegateResult = {
  ok: true,
  provider: "opencode",
  stdout: "pong from opencode",
  stderr: "",
  exitCode: 0,
};

beforeEach(() => {
  mockRunProvider.mockResolvedValue(claudeResult);
});

describe("validateInput", () => {
  it("rejects missing prompt", () => {
    expect(() => validateInput({})).toThrow();
  });

  it("rejects empty prompt", () => {
    expect(() => validateInput({ prompt: "" })).toThrow();
  });

  it("accepts valid input with defaults", () => {
    const r = validateInput({ prompt: "hello" });
    expect(r.prompt).toBe("hello");
    expect(r.json).toBe(false);
    expect(r.provider).toBe("claude");
  });

  it("accepts codex provider", () => {
    const r = validateInput({ prompt: "hello", provider: "codex" });
    expect(r.provider).toBe("codex");
  });

  it("accepts antigravity provider", () => {
    const r = validateInput({ prompt: "hello", provider: "antigravity" });
    expect(r.provider).toBe("antigravity");
  });

  it("accepts opencode provider", () => {
    const r = validateInput({ prompt: "hello", provider: "opencode" });
    expect(r.provider).toBe("opencode");
  });

  it("accepts model", () => {
    const r = validateInput({ prompt: "hello", model: "sonnet" });
    expect(r.model).toBe("sonnet");
  });

  it("rejects empty model", () => {
    expect(() => validateInput({ prompt: "hello", model: "" })).toThrow();
  });

  it("rejects unknown provider", () => {
    expect(() => validateInput({ prompt: "hello", provider: "gpt4" })).toThrow();
  });

  it("default models are listed in PROVIDER_MODELS", () => {
    for (const provider of PROVIDERS) {
      expect(PROVIDER_MODELS[provider]).toContain(DEFAULT_PROVIDER_MODELS[provider]);
    }
  });
});

describe("delegate", () => {
  it("routes to claude by default", async () => {
    const result = await delegate({ prompt: "say only the word pong" });
    expect(result.ok).toBe(true);
    expect(mockRunProvider).toHaveBeenCalledWith(
      "claude",
      "say only the word pong",
      DEFAULT_PROVIDER_MODELS.claude,
    );
  });

  it("routes to codex when provider=codex", async () => {
    mockRunProvider.mockResolvedValue(codexResult);
    const result = await delegate({ prompt: "say pong", provider: "codex" });
    expect(result.ok).toBe(true);
    expect(result.provider).toBe("codex");
    expect(mockRunProvider).toHaveBeenCalledWith(
      "codex",
      "say pong",
      DEFAULT_PROVIDER_MODELS.codex,
    );
  });

  it("routes model to selected provider", async () => {
    const result = await delegate({
      prompt: "say pong",
      provider: "codex",
      model: "gpt-5.1-codex",
    });
    expect(result.ok).toBe(true);
    expect(mockRunProvider).toHaveBeenCalledWith("codex", "say pong", "gpt-5.1-codex");
  });

  it("routes to antigravity when provider=antigravity", async () => {
    mockRunProvider.mockResolvedValue(antigravityResult);
    const result = await delegate({ prompt: "say pong", provider: "antigravity" });
    expect(result.ok).toBe(true);
    expect(result.provider).toBe("antigravity");
    expect(mockRunProvider).toHaveBeenCalledWith(
      "antigravity",
      "say pong",
      DEFAULT_PROVIDER_MODELS.antigravity,
    );
  });

  it("routes to opencode when provider=opencode", async () => {
    mockRunProvider.mockResolvedValue(opencodeResult);
    const result = await delegate({ prompt: "say pong", provider: "opencode" });
    expect(result.ok).toBe(true);
    expect(result.provider).toBe("opencode");
    expect(mockRunProvider).toHaveBeenCalledWith(
      "opencode",
      "say pong",
      DEFAULT_PROVIDER_MODELS.opencode,
    );
  });

  it("propagates validation error on invalid input", async () => {
    await expect(delegate({})).rejects.toThrow();
  });
});
