import { execa } from "execa";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { runProvider as runAntigravity } from "../src/providers/antigravity.js";
import { runProvider as runClaude } from "../src/providers/claude.js";
import { runProvider as runCodex } from "../src/providers/codex.js";
import { runProvider as runCursor } from "../src/providers/cursor.js";

vi.mock("execa", () => ({
  execa: vi.fn(),
}));

const mockExeca = vi.mocked(execa);

beforeEach(() => {
  vi.clearAllMocks();
  mockExeca.mockResolvedValue({ stdout: "pong", stderr: "", exitCode: 0 } as Awaited<
    ReturnType<typeof execa>
  >);
});

describe("providers", () => {
  it("passes model to claude", async () => {
    await runClaude("say pong", "sonnet");

    expect(mockExeca).toHaveBeenCalledWith(
      "claude",
      ["--print", "--model", "sonnet", "say pong"],
      expect.objectContaining({ extendEnv: false, stdin: "ignore" }),
    );
  });

  it("passes model to codex", async () => {
    await runCodex("say pong", "gpt-5.1-codex");

    const [, args, options] = mockExeca.mock.calls[0] as unknown as [
      string,
      string[],
      Record<string, unknown>,
    ];
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

  it("pipes prompt to agy via stdin", async () => {
    await runAntigravity("say pong", "Gemini 3.1 Pro (High)");

    expect(mockExeca).toHaveBeenCalledWith("agy", ["-p", "--model", "Gemini 3.1 Pro (High)"], {
      input: "say pong",
    });
  });

  it("runs cursor via the delegate script and extracts the result block", async () => {
    mockExeca.mockResolvedValue({
      stdout: "[cursor:init] model=composer-2.5\n[cursor:tool] 1 readToolCall README.md\n[cursor:result]\nthe answer\nspans two lines\n[cursor:done] 4s",
      stderr: "",
      exitCode: 0,
    } as Awaited<ReturnType<typeof execa>>);

    const result = await runCursor("say pong", "composer-2.5");

    const [bin, args, options] = mockExeca.mock.calls[0] as unknown as [
      string,
      string[],
      Record<string, unknown>,
    ];
    expect(bin).toBe("bash");
    expect(args[0]).toContain("cursor-delegate/cursor-delegate.sh");
    expect(args[1]).toBe("ask");
    expect(args[2]).toBe("say pong");
    expect((options.env as Record<string, string>).CURSOR_MODEL).toBe("composer-2.5");
    expect(result.ok).toBe(true);
    expect(result.stdout).toBe("the answer\nspans two lines");
  });

  it("fails when cursor produces no result block", async () => {
    mockExeca.mockResolvedValue({
      stdout: "[cursor:init] model=composer-2.5\n[cursor:tool] 1 readToolCall README.md",
      stderr: "",
      exitCode: 0,
    } as Awaited<ReturnType<typeof execa>>);

    const result = await runCursor("say pong", "composer-2.5");

    expect(result.ok).toBe(false);
    expect(result.stderr).toContain("no [cursor:result]");
  });

  it("fails when agy returns empty stdout", async () => {
    mockExeca.mockResolvedValue({ stdout: "", stderr: "", exitCode: 0 } as Awaited<
      ReturnType<typeof execa>
    >);

    const result = await runAntigravity("say pong", "Gemini 3.1 Pro (High)");

    expect(result.ok).toBe(false);
    expect(result.stderr).toContain("empty output");
  });
});
