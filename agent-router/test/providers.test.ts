import { describe, it, expect, vi, beforeEach } from "vitest";
import { execa } from "execa";
import { runProvider as runClaude } from "../src/providers/claude.js";
import { runProvider as runCodex } from "../src/providers/codex.js";

vi.mock("execa", () => ({
  execa: vi.fn(),
}));

const mockExeca = vi.mocked(execa);

beforeEach(() => {
  vi.clearAllMocks();
  mockExeca.mockResolvedValue({ stdout: "pong", stderr: "", exitCode: 0 } as Awaited<ReturnType<typeof execa>>);
});

describe("providers", () => {
  it("passes model to claude", async () => {
    await runClaude("say pong", "sonnet");

    expect(mockExeca).toHaveBeenCalledWith(
      "claude",
      ["--print", "--model", "sonnet", "say pong"],
      expect.objectContaining({ extendEnv: false })
    );
  });

  it("passes model to codex", async () => {
    await runCodex("say pong", "gpt-5.1-codex");

    const [, args, options] = mockExeca.mock.calls[0] as unknown as [string, string[], Record<string, unknown>];
    expect(args).toEqual([
      "exec",
      "--output-last-message",
      expect.stringContaining("output.txt"),
      "--ephemeral",
      "--model",
      "gpt-5.1-codex",
      "say pong",
    ]);
    expect(options).toEqual(expect.objectContaining({ extendEnv: false, stdin: "ignore" }));
  });
});
