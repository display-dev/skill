#!/usr/bin/env node
// bin/transform.mjs — mirror the canonical `display-dev/` skill to the
// distribution mounts, substituting per-mount placeholders.
//
// Replaces the previous `rsync -a --delete` loop in sync-mounts.sh. The
// node transformer adds two things rsync can't: per-mount placeholder
// substitution (so a host like Codex can carry slightly different copy
// without hand-editing a generated mount) and a content+mode `--check`
// gate for CI.
//
// Usage:
//   node bin/transform.mjs                          # write resolved mounts
//   node bin/transform.mjs --check                  # CI gate: exit 1 on drift
//   node bin/transform.mjs --output-root <path>     # write to an alternate
//                                                   #   root (byte-equivalence
//                                                   #   testing without
//                                                   #   touching committed mounts)
//
// Substitution applies to .md / .html files only; everything else
// (scripts, the bundled jq binaries) is byte-copied. File mode is
// preserved per file via chmodSync — the helper scripts and jq binaries
// must stay executable. Stale-file cleanup is per-mount: files present in
// a mount but absent from canonical are deleted in write mode and reported
// as drift in --check.

import { readdirSync, readFileSync, writeFileSync, mkdirSync, statSync, existsSync, rmSync, chmodSync } from 'node:fs';
import { join, dirname, relative, resolve, sep, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';

// =============================================================================
// Tables
// =============================================================================

// Frontmatter field set the canonical display-dev/SKILL.md is expected to
// carry. Backs an exact-set assertion on every resolved mount so a stray
// field add/remove is caught before it lands in a mount. Value drift and
// reordering are caught by the byte-equivalence comparison in --check.
const EXPECTED_FRONTMATTER_FIELDS = ['name', 'description'];

// Per-mount placeholder values. Keys are the placeholder names (without the
// `{{ }}` delimiters); values are the literal text substituted into that
// mount's .md/.html files. The three generic mounts share one host-neutral
// set; the Codex plugin's bundled skill copy gets Codex-specific wording.
const GENERIC_PLACEHOLDERS = {
  host_generated_phrase: 'publish what the agent just generated',
  host_artifact_name: 'an artifact',
  mcp_preference_note:
    'When an MCP server is available, it may be used for supported publish/share/comment workflows; otherwise use the helpers or CLI.',
};

const PROVIDER_PLACEHOLDERS = {
  skills: GENERIC_PLACEHOLDERS,
  hermes: GENERIC_PLACEHOLDERS,
  pi: GENERIC_PLACEHOLDERS,
  codex_skill: {
    host_generated_phrase: 'publish what Codex just generated',
    host_artifact_name: 'a Codex artifact',
    mcp_preference_note:
      'In the Codex plugin, the remote display.dev MCP server is bundled. Prefer it for supported publish/share/comment workflows after OAuth succeeds; use helpers or CLI for local files, CI, or when MCP is unavailable.',
  },
};

// Source of truth for which `{{...}}` tokens the transformer resolves. Adding
// a placeholder is one entry here plus one value per provider above.
const PLACEHOLDER_KEYS = ['host_generated_phrase', 'host_artifact_name', 'mcp_preference_note'];

// Per-mount config: provider (keys PROVIDER_PLACEHOLDERS), path (output root
// relative to outputRoot), displayName (CLI output label).
const MOUNTS = [
  { provider: 'skills',      path: 'skills/display-dev',                   displayName: 'npm skills' },
  { provider: 'hermes',      path: 'hermes/productivity/display.dev',      displayName: 'Hermes' },
  { provider: 'pi',          path: 'pi/agent/skills/display-dev',          displayName: 'Pi' },
  { provider: 'codex_skill', path: 'codex/display-dev/skills/display-dev', displayName: 'Codex plugin skill' },
];

// Substitution is scoped to authoring formats. Everything else (scripts, the
// bundled jq binaries, licenses) is byte-copied untouched.
const TEXT_EXTENSIONS_FOR_SUBSTITUTION = new Set(['.md', '.html']);

// Single regex pass across all placeholders. Guarded: with no keys the regex
// would be malformed, so substitution is skipped entirely when the set is empty.
const PLACEHOLDER_REGEX = PLACEHOLDER_KEYS.length
  ? new RegExp(`\\{\\{(${PLACEHOLDER_KEYS.join('|')})\\}\\}`, 'g')
  : null;

// =============================================================================
// Paths
// =============================================================================

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const CANONICAL = join(ROOT, 'display-dev');

// =============================================================================
// Filesystem helpers
// =============================================================================

function* walk(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      yield* walk(full);
    } else if (entry.isFile()) {
      yield full;
    }
  }
}

function shouldSubstitute(path) {
  if (!PLACEHOLDER_REGEX) {
    return false;
  }
  const dot = path.lastIndexOf('.');
  if (dot === -1) {
    return false;
  }
  return TEXT_EXTENSIONS_FOR_SUBSTITUTION.has(path.slice(dot));
}

function listFiles(dir) {
  if (!existsSync(dir)) {
    return new Set();
  }
  const files = new Set();
  for (const f of walk(dir)) {
    files.add(relative(dir, f));
  }
  return files;
}

// =============================================================================
// Substitution
// =============================================================================

function replacePlaceholders(content, providerKey) {
  const placeholders = PROVIDER_PLACEHOLDERS[providerKey];
  if (!placeholders) {
    throw new Error(`Unknown provider: ${providerKey}`);
  }
  return content.replace(PLACEHOLDER_REGEX, (match, key) => {
    const value = placeholders[key];
    if (value === undefined) {
      throw new Error(`Provider ${providerKey} has no value for placeholder {{${key}}}`);
    }
    return value;
  });
}

// =============================================================================
// Invariants
// =============================================================================

// Asserts no unresolved {{...}} remains in resolved output. Lives on the
// shared resolve/write path (not just --check) so a `{{typo}}` in canonical
// fails the write before bad bytes ever land in a mount.
function assertNoUnresolvedPlaceholders(content, relPath) {
  const match = content.match(/\{\{[^}]*\}\}/);
  if (match) {
    throw new Error(`Unresolved placeholder in ${relPath}: ${match[0]} (at byte index ${match.index})`);
  }
}

// Extracts top-level YAML frontmatter field names (in document order) from
// SKILL.md content. Field-name extraction only — values are ignored. Top-level
// = column-0 `key:` lines; indented continuation lines are skipped.
function extractFrontmatterFieldNames(content) {
  const match = content.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n/);
  if (!match) {
    throw new Error('SKILL.md is missing YAML frontmatter');
  }
  const fields = [];
  for (const line of match[1].split(/\r?\n/)) {
    const fieldMatch = line.match(/^([a-zA-Z][a-zA-Z0-9_-]*):/);
    if (fieldMatch) {
      fields.push(fieldMatch[1]);
    }
  }
  return fields;
}

// Asserts the resolved SKILL.md frontmatter has the exact field set
// EXPECTED_FRONTMATTER_FIELDS — no missing, no extras.
function assertExpectedFrontmatterFields(content, label) {
  const actual = new Set(extractFrontmatterFieldNames(content));
  const expected = new Set(EXPECTED_FRONTMATTER_FIELDS);

  const missing = [...expected].filter((f) => !actual.has(f));
  const extras = [...actual].filter((f) => !expected.has(f));

  if (missing.length || extras.length) {
    const parts = [];
    if (missing.length) {
      parts.push(`missing: ${missing.join(', ')}`);
    }
    if (extras.length) {
      parts.push(`extras: ${extras.join(', ')}`);
    }
    throw new Error(`${label} frontmatter field-set drift — ${parts.join('; ')}`);
  }
}

// =============================================================================
// Factory
// =============================================================================

/**
 * Creates a transform function for one mount.
 *
 * @param {Object} config
 * @param {string} config.provider - keys PROVIDER_PLACEHOLDERS
 * @param {string} config.path - mount output path (relative to outputRoot)
 * @param {string} config.displayName - shown in CLI output
 * @param {string} config.outputRoot - absolute output root
 * @param {boolean} config.checkMode - if true, compare instead of write
 * @returns {() => { displayName, mountPath, written, drift }} transform fn
 */
function createTransformer(config) {
  const { provider, path: mountPath, displayName, outputRoot, checkMode } = config;
  const mountDir = join(outputRoot, mountPath);

  return function transform() {
    const canonicalFiles = listFiles(CANONICAL);
    const mountFiles = listFiles(mountDir);

    let drift = 0;
    let written = 0;

    for (const rel of canonicalFiles) {
      const srcPath = join(CANONICAL, rel);
      const dstPath = join(mountDir, rel);
      const srcMode = statSync(srcPath).mode;
      const srcBuf = readFileSync(srcPath);

      let resolved;
      if (shouldSubstitute(rel)) {
        const replaced = replacePlaceholders(srcBuf.toString('utf8'), provider);
        assertNoUnresolvedPlaceholders(replaced, `${mountPath}/${rel}`);
        resolved = Buffer.from(replaced, 'utf8');
      } else {
        resolved = srcBuf;
      }

      if (checkMode) {
        if (!existsSync(dstPath)) {
          console.error(`missing in ${mountPath}: ${rel}`);
          drift++;
          continue;
        }
        const existingStat = statSync(dstPath);
        const existing = readFileSync(dstPath);
        if (!existing.equals(resolved)) {
          console.error(`drift in ${mountPath}: ${rel}`);
          drift++;
        } else if ((existingStat.mode & 0o777) !== (srcMode & 0o777)) {
          console.error(`mode drift in ${mountPath}: ${rel} (${(existingStat.mode & 0o777).toString(8)} vs ${(srcMode & 0o777).toString(8)})`);
          drift++;
        }
      } else {
        mkdirSync(dirname(dstPath), { recursive: true });
        writeFileSync(dstPath, resolved);
        chmodSync(dstPath, srcMode & 0o777);
        written++;
      }
    }

    // Stale-file cleanup: files in the mount with no canonical counterpart.
    // Write mode deletes them; --check reports as drift.
    for (const rel of mountFiles) {
      if (canonicalFiles.has(rel)) {
        continue;
      }
      const dstPath = join(mountDir, rel);
      if (checkMode) {
        console.error(`stale in ${mountPath}: ${rel}`);
        drift++;
      } else {
        rmSync(dstPath, { force: true });
      }
    }

    return { displayName, mountPath, written, drift };
  };
}

// =============================================================================
// CLI
// =============================================================================

function parseArgs(argv) {
  const args = { checkMode: false, outputRoot: ROOT };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--check') {
      args.checkMode = true;
    } else if (argv[i] === '--output-root') {
      const raw = argv[++i];
      if (!raw) {
        throw new Error('--output-root requires a path argument');
      }
      // Resolve relative paths against CWD so the factory contract
      // (outputRoot is absolute) holds regardless of how the CLI is invoked.
      args.outputRoot = resolve(raw);
    } else {
      throw new Error(`Unknown argument: ${argv[i]}`);
    }
  }
  // Reject output roots inside the canonical source tree — writing a mount
  // there would pollute the next mount's walk and silently break
  // byte-equivalence.
  const relToCanonical = relative(CANONICAL, args.outputRoot);
  const escapesCanonical = relToCanonical === '..' || relToCanonical.startsWith(`..${sep}`) || isAbsolute(relToCanonical);
  if (!escapesCanonical) {
    throw new Error(`--output-root must not point inside canonical (${CANONICAL}); got ${args.outputRoot}`);
  }
  return args;
}

function main() {
  const { checkMode, outputRoot } = parseArgs(process.argv.slice(2));

  let totalWritten = 0;
  let totalDrift = 0;

  for (const mount of MOUNTS) {
    const transform = createTransformer({ ...mount, outputRoot, checkMode });
    const result = transform();
    totalWritten += result.written;
    totalDrift += result.drift;

    if (!checkMode) {
      console.log(`✓ ${result.displayName}: ${result.written} files → ${result.mountPath}/`);
    }

    // Per-mount --check assertion: resolved frontmatter has the exact
    // expected field set. Skipped on first run (no committed mount yet);
    // the byte-equivalence loop above already reports missing-files drift.
    if (checkMode) {
      const mountSkillPath = join(outputRoot, mount.path, 'SKILL.md');
      if (existsSync(mountSkillPath)) {
        const mountContent = readFileSync(mountSkillPath, 'utf8');
        assertExpectedFrontmatterFields(mountContent, mount.path);
      }
    }
  }

  if (checkMode) {
    if (totalDrift) {
      console.error('');
      console.error('Mount drift detected. Run `bin/sync-mounts.sh` (no --check) to regenerate.');
      process.exit(1);
    }
    console.log(`OK · ${MOUNTS.length} mounts match canonical (resolved)`);
  } else {
    console.log(`Wrote ${totalWritten} files across ${MOUNTS.length} mounts`);
  }
}

try {
  main();
} catch (err) {
  console.error(`error: ${err.message}`);
  process.exit(1);
}
