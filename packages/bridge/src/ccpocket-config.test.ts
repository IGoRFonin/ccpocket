import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { join } from "node:path";
import { mkdirSync, writeFileSync, rmSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { tmpdir } from "node:os";
import {
  parseCcpocketConfig,
  toGtrConfig,
  buildSandboxSettings,
} from "./ccpocket-config.js";

describe("parseCcpocketConfig", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = join(tmpdir(), `ccpocket-cfg-${randomUUID().slice(0, 8)}`);
    mkdirSync(tempDir, { recursive: true });
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
  });

  it("returns empty config when file is missing", () => {
    const config = parseCcpocketConfig(tempDir);
    expect(config).toEqual({});
  });

  it("parses full sandbox section", () => {
    writeFileSync(
      join(tempDir, ".ccpocket.toml"),
      `
[sandbox]
autoAllowBash = true
allowUnsandboxedCommands = false

[sandbox.network]
allowLocalBinding = true
allowedDomains = ["api.github.com", "registry.npmjs.org"]

[sandbox.filesystem]
allowWrite = ["/tmp/build"]
denyWrite = ["/etc"]
denyRead = ["/etc/secrets"]
`,
    );

    const config = parseCcpocketConfig(tempDir);
    expect(config.sandbox).toEqual({
      autoAllowBash: true,
      allowUnsandboxedCommands: false,
      network: {
        allowLocalBinding: true,
        allowedDomains: ["api.github.com", "registry.npmjs.org"],
      },
      filesystem: {
        allowWrite: ["/tmp/build"],
        denyWrite: ["/etc"],
        denyRead: ["/etc/secrets"],
      },
    });
  });

  it("parses full worktree section", () => {
    writeFileSync(
      join(tempDir, ".ccpocket.toml"),
      `
[worktree.copy]
include = [".claude/settings.local.json", "local.properties"]
exclude = ["*.tmp"]
includeDirs = ["node_modules"]
excludeDirs = [".git"]

[worktree.hooks]
postCreate = "flutter pub get"
preRemove = "echo cleanup"
`,
    );

    const config = parseCcpocketConfig(tempDir);
    expect(config.worktree).toEqual({
      copy: {
        include: [".claude/settings.local.json", "local.properties"],
        exclude: ["*.tmp"],
        includeDirs: ["node_modules"],
        excludeDirs: [".git"],
      },
      hooks: {
        postCreate: "flutter pub get",
        preRemove: "echo cleanup",
      },
    });
  });

  it("parses only sandbox (no worktree section)", () => {
    writeFileSync(
      join(tempDir, ".ccpocket.toml"),
      `
[sandbox]
autoAllowBash = false
`,
    );
    const config = parseCcpocketConfig(tempDir);
    expect(config.sandbox).toEqual({ autoAllowBash: false });
    expect(config.worktree).toBeUndefined();
  });

  it("parses only worktree (no sandbox section)", () => {
    writeFileSync(
      join(tempDir, ".ccpocket.toml"),
      `
[worktree.copy]
include = ["foo.txt"]
`,
    );
    const config = parseCcpocketConfig(tempDir);
    expect(config.sandbox).toBeUndefined();
    expect(config.worktree?.copy?.include).toEqual(["foo.txt"]);
  });

  it("handles malformed TOML gracefully", () => {
    writeFileSync(join(tempDir, ".ccpocket.toml"), "{{invalid toml}}");
    const config = parseCcpocketConfig(tempDir);
    expect(config).toEqual({});
  });

  it("supports hooks as arrays", () => {
    writeFileSync(
      join(tempDir, ".ccpocket.toml"),
      `
[worktree.hooks]
postCreate = ["npm install", "flutter pub get"]
preRemove = ["echo bye"]
`,
    );
    const config = parseCcpocketConfig(tempDir);
    expect(config.worktree?.hooks?.postCreate).toEqual(["npm install", "flutter pub get"]);
    expect(config.worktree?.hooks?.preRemove).toEqual(["echo bye"]);
  });
});

describe("toGtrConfig", () => {
  it("converts worktree config to GtrConfig", () => {
    const gtr = toGtrConfig({
      worktree: {
        copy: {
          include: ["a.txt", "b.txt"],
          includeDirs: ["node_modules"],
        },
        hooks: {
          postCreate: "npm install",
        },
      },
    });

    expect(gtr.copy.include).toEqual(["a.txt", "b.txt"]);
    expect(gtr.copy.exclude).toEqual([]);
    expect(gtr.copy.includeDirs).toEqual(["node_modules"]);
    expect(gtr.copy.excludeDirs).toEqual([]);
    expect(gtr.hook.postCreate).toEqual(["npm install"]);
    expect(gtr.hook.preRemove).toEqual([]);
  });

  it("converts array hooks", () => {
    const gtr = toGtrConfig({
      worktree: {
        hooks: {
          postCreate: ["cmd1", "cmd2"],
          preRemove: ["rm -rf tmp"],
        },
      },
    });
    expect(gtr.hook.postCreate).toEqual(["cmd1", "cmd2"]);
    expect(gtr.hook.preRemove).toEqual(["rm -rf tmp"]);
  });

  it("returns empty GtrConfig for empty worktree", () => {
    const gtr = toGtrConfig({});
    expect(gtr.copy.include).toEqual([]);
    expect(gtr.hook.postCreate).toEqual([]);
  });
});

describe("buildSandboxSettings", () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = join(tmpdir(), `ccpocket-sandbox-${randomUUID().slice(0, 8)}`);
    mkdirSync(tempDir, { recursive: true });
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
  });

  it("returns defaults when no config file exists", () => {
    const settings = buildSandboxSettings(tempDir);
    expect(settings.enabled).toBe(true);
    expect(settings.autoAllowBashIfSandboxed).toBe(true);
    expect(settings.allowUnsandboxedCommands).toBe(false);
  });

  it("merges project config over defaults", () => {
    writeFileSync(
      join(tempDir, ".ccpocket.toml"),
      `
[sandbox]
autoAllowBash = false
allowUnsandboxedCommands = true

[sandbox.network]
allowedDomains = ["example.com"]
`,
    );

    const settings = buildSandboxSettings(tempDir);
    expect(settings.enabled).toBe(true);
    expect(settings.autoAllowBashIfSandboxed).toBe(false);
    expect(settings.allowUnsandboxedCommands).toBe(true);
    expect(settings.network?.allowedDomains).toEqual(["example.com"]);
  });

  it("includes filesystem settings", () => {
    writeFileSync(
      join(tempDir, ".ccpocket.toml"),
      `
[sandbox.filesystem]
allowWrite = ["/tmp/out"]
denyRead = ["/secrets"]
`,
    );

    const settings = buildSandboxSettings(tempDir);
    expect(settings.filesystem?.allowWrite).toEqual(["/tmp/out"]);
    expect(settings.filesystem?.denyRead).toEqual(["/secrets"]);
  });
});
