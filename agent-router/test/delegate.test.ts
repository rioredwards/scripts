import { describe, it, expect, vi, beforeEach } from "vitest";
import { delegate, validateInput } from "../src/delegate.js";
import type { DelegateResult } from "../src/schema.js";

vi.mock("../src/provider.js", () => ({
  PROVIDER_NAME: "claude",
  runProvider: vi.fn(),
}));

import { runProvider } from "../src/provider.js";
const mockRunProvider = vi.mocked(runProvider);

const successResult: DelegateResult = {
  ok: true,
  provider: "claude",
  stdout: "pong",
  stderr: "",
  exitCode: 0,
};

beforeEach(() => {
  mockRunProvider.mockResolvedValue(successResult);
});

describe("validateInput", () => {
  it("rejects missing prompt", () => {
    expect(() => validateInput({})).toThrow();
  });

  it("rejects empty prompt", () => {
    expect(() => validateInput({ prompt: "" })).toThrow();
  });

  it("accepts valid input", () => {
    const result = validateInput({ prompt: "hello" });
    expect(result.prompt).toBe("hello");
    expect(result.json).toBe(false);
  });
});

describe("delegate", () => {
  it("happy path: passes prompt to provider and returns result", async () => {
    const result = await delegate({ prompt: "say only the word pong" });
    expect(result.ok).toBe(true);
    expect(result.provider).toBe("claude");
    expect(result.stdout).toBe("pong");
    expect(result.exitCode).toBe(0);
    expect(mockRunProvider).toHaveBeenCalledWith("say only the word pong");
  });

  it("propagates validation error on invalid input", async () => {
    await expect(delegate({})).rejects.toThrow();
  });
});
