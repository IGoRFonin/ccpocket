/**
 * .ccpocket.toml — Unified project configuration parser.
 *
 * Resolution order:
 *   worktree: .ccpocket.toml [worktree] > .gtrconfig (backward compat)
 *   sandbox:  project .ccpocket.toml > global ~/.ccpocket.toml > built-in defaults
 */

import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { parse as parseTOML } from "smol-toml";
import type { GtrConfig } from "./worktree.js";
import type { SandboxSettings } from "@anthropic-ai/claude-agent-sdk";

// ---- Config Types ----

export interface SandboxConfig {
  autoAllowBash?: boolean;
  allowUnsandboxedCommands?: boolean;
  network?: {
    allowLocalBinding?: boolean;
    allowedDomains?: string[];
    allowUnixSockets?: string[];
    allowAllUnixSockets?: boolean;
  };
  filesystem?: {
    allowWrite?: string[];
    denyWrite?: string[];
    denyRead?: string[];
  };
}

export interface WorktreeConfig {
  copy?: {
    include?: string[];
    exclude?: string[];
    includeDirs?: string[];
    excludeDirs?: string[];
  };
  hooks?: {
    postCreate?: string | string[];
    preRemove?: string | string[];
  };
}

export interface CcpocketConfig {
  sandbox?: SandboxConfig;
  worktree?: WorktreeConfig;
}

// ---- Built-in defaults ----

const DEFAULT_SANDBOX: SandboxConfig = {
  autoAllowBash: true,
  allowUnsandboxedCommands: false,
};

// ---- Parsing ----

/**
 * Parse a .ccpocket.toml file at the given path.
 * Returns an empty config on missing file or parse error.
 */
function parseTomlFile(filePath: string): CcpocketConfig {
  if (!existsSync(filePath)) return {};
  try {
    const content = readFileSync(filePath, "utf-8");
    const raw = parseTOML(content) as Record<string, unknown>;
    return validateConfig(raw);
  } catch (err) {
    console.warn(`[ccpocket-config] Failed to parse ${filePath}:`, err);
    return {};
  }
}

/** Validate and coerce raw TOML into CcpocketConfig. */
function validateConfig(raw: Record<string, unknown>): CcpocketConfig {
  const config: CcpocketConfig = {};

  // ---- sandbox ----
  if (raw.sandbox && typeof raw.sandbox === "object" && !Array.isArray(raw.sandbox)) {
    const s = raw.sandbox as Record<string, unknown>;
    const sandbox: SandboxConfig = {};

    if (typeof s.autoAllowBash === "boolean") sandbox.autoAllowBash = s.autoAllowBash;
    if (typeof s.allowUnsandboxedCommands === "boolean") sandbox.allowUnsandboxedCommands = s.allowUnsandboxedCommands;

    // network
    if (s.network && typeof s.network === "object" && !Array.isArray(s.network)) {
      const n = s.network as Record<string, unknown>;
      sandbox.network = {};
      if (typeof n.allowLocalBinding === "boolean") sandbox.network.allowLocalBinding = n.allowLocalBinding;
      if (Array.isArray(n.allowedDomains)) sandbox.network.allowedDomains = n.allowedDomains.filter((d): d is string => typeof d === "string");
      if (Array.isArray(n.allowUnixSockets)) sandbox.network.allowUnixSockets = n.allowUnixSockets.filter((d): d is string => typeof d === "string");
      if (typeof n.allowAllUnixSockets === "boolean") sandbox.network.allowAllUnixSockets = n.allowAllUnixSockets;
    }

    // filesystem
    if (s.filesystem && typeof s.filesystem === "object" && !Array.isArray(s.filesystem)) {
      const f = s.filesystem as Record<string, unknown>;
      sandbox.filesystem = {};
      if (Array.isArray(f.allowWrite)) sandbox.filesystem.allowWrite = f.allowWrite.filter((d): d is string => typeof d === "string");
      if (Array.isArray(f.denyWrite)) sandbox.filesystem.denyWrite = f.denyWrite.filter((d): d is string => typeof d === "string");
      if (Array.isArray(f.denyRead)) sandbox.filesystem.denyRead = f.denyRead.filter((d): d is string => typeof d === "string");
    }

    config.sandbox = sandbox;
  }

  // ---- worktree ----
  if (raw.worktree && typeof raw.worktree === "object" && !Array.isArray(raw.worktree)) {
    const w = raw.worktree as Record<string, unknown>;
    const worktree: WorktreeConfig = {};

    // copy
    if (w.copy && typeof w.copy === "object" && !Array.isArray(w.copy)) {
      const c = w.copy as Record<string, unknown>;
      worktree.copy = {};
      if (Array.isArray(c.include)) worktree.copy.include = c.include.filter((d): d is string => typeof d === "string");
      if (Array.isArray(c.exclude)) worktree.copy.exclude = c.exclude.filter((d): d is string => typeof d === "string");
      if (Array.isArray(c.includeDirs)) worktree.copy.includeDirs = c.includeDirs.filter((d): d is string => typeof d === "string");
      if (Array.isArray(c.excludeDirs)) worktree.copy.excludeDirs = c.excludeDirs.filter((d): d is string => typeof d === "string");
    }

    // hooks
    if (w.hooks && typeof w.hooks === "object" && !Array.isArray(w.hooks)) {
      const h = w.hooks as Record<string, unknown>;
      worktree.hooks = {};
      if (typeof h.postCreate === "string") worktree.hooks.postCreate = h.postCreate;
      else if (Array.isArray(h.postCreate)) worktree.hooks.postCreate = h.postCreate.filter((d): d is string => typeof d === "string");
      if (typeof h.preRemove === "string") worktree.hooks.preRemove = h.preRemove;
      else if (Array.isArray(h.preRemove)) worktree.hooks.preRemove = h.preRemove.filter((d): d is string => typeof d === "string");
    }

    config.worktree = worktree;
  }

  return config;
}

// ---- Public API ----

/** Parse project-level .ccpocket.toml */
export function parseCcpocketConfig(projectPath: string): CcpocketConfig {
  return parseTomlFile(join(projectPath, ".ccpocket.toml"));
}

/** Parse global ~/.ccpocket.toml */
export function parseGlobalCcpocketConfig(): CcpocketConfig {
  return parseTomlFile(join(homedir(), ".ccpocket.toml"));
}

/** Convert .ccpocket.toml [worktree] section to the existing GtrConfig shape. */
export function toGtrConfig(config: CcpocketConfig): GtrConfig {
  const w = config.worktree;
  const toArray = (v: string | string[] | undefined): string[] => {
    if (!v) return [];
    return typeof v === "string" ? [v] : v;
  };
  return {
    copy: {
      include: w?.copy?.include ?? [],
      exclude: w?.copy?.exclude ?? [],
      includeDirs: w?.copy?.includeDirs ?? [],
      excludeDirs: w?.copy?.excludeDirs ?? [],
    },
    hook: {
      postCreate: toArray(w?.hooks?.postCreate),
      preRemove: toArray(w?.hooks?.preRemove),
    },
  };
}

/**
 * Build SDK SandboxSettings by merging project config, global config, and defaults.
 * Priority: project > global > defaults.
 *
 * `enabled` is always set to `true` (caller should only invoke this when sandbox is on).
 */
export function buildSandboxSettings(projectPath: string): SandboxSettings {
  const project = parseCcpocketConfig(projectPath);
  const global = parseGlobalCcpocketConfig();

  // Merge: project overrides global overrides defaults
  const merged: SandboxConfig = {
    ...DEFAULT_SANDBOX,
    ...global.sandbox,
    ...project.sandbox,
  };

  // Deep-merge network & filesystem (shallow spread only covers top-level)
  if (project.sandbox?.network || global.sandbox?.network) {
    merged.network = {
      ...global.sandbox?.network,
      ...project.sandbox?.network,
    };
  }
  if (project.sandbox?.filesystem || global.sandbox?.filesystem) {
    merged.filesystem = {
      ...global.sandbox?.filesystem,
      ...project.sandbox?.filesystem,
    };
  }

  // Map to SDK SandboxSettings
  const settings: SandboxSettings = {
    enabled: true,
    autoAllowBashIfSandboxed: merged.autoAllowBash,
    allowUnsandboxedCommands: merged.allowUnsandboxedCommands,
  };

  if (merged.network) {
    settings.network = {
      ...(merged.network.allowLocalBinding != null ? { allowLocalBinding: merged.network.allowLocalBinding } : {}),
      ...(merged.network.allowedDomains ? { allowedDomains: merged.network.allowedDomains } : {}),
      ...(merged.network.allowUnixSockets ? { allowUnixSockets: merged.network.allowUnixSockets } : {}),
      ...(merged.network.allowAllUnixSockets != null ? { allowAllUnixSockets: merged.network.allowAllUnixSockets } : {}),
    };
  }

  if (merged.filesystem) {
    settings.filesystem = {
      ...(merged.filesystem.allowWrite ? { allowWrite: merged.filesystem.allowWrite } : {}),
      ...(merged.filesystem.denyWrite ? { denyWrite: merged.filesystem.denyWrite } : {}),
      ...(merged.filesystem.denyRead ? { denyRead: merged.filesystem.denyRead } : {}),
    };
  }

  return settings;
}
