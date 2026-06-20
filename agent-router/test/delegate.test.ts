import { describe, it, expect, vi, beforeEach } from "vitest";
import { delegate, validateInput } from "../src/delegate.js";
import type { DelegateResult } from "../src/schema.js";

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

  it("rejects unknown provider", () => {
    expect(() => validateInput({ prompt: "hello", provider: "gpt4" })).toThrow();
  });
});

describe("delegate", () => {
  it("routes to claude by default", async () => {
    const result = await delegate({ prompt: "say only the word pong" });
    expect(result.ok).toBe(true);
    expect(mockRunProvider).toHaveBeenCalledWith("claude", "say only the word pong");
  });

  it("routes to codex when provider=codex", async () => {
    mockRunProvider.mockResolvedValue(codexResult);
    const result = await delegate({ prompt: "say pong", provider: "codex" });
    expect(result.ok).toBe(true);
    expect(result.provider).toBe("codex");
    expect(mockRunProvider).toHaveBeenCalledWith("codex", "say pong");
  });

  it("propagates validation error on invalid input", async () => {
    await expect(delegate({})).rejects.toThrow();
  });
});
