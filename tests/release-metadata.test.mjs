import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';

test('published checksums bind both assets to their exact dated release', (t) => {
  const root = path.resolve(import.meta.dirname, '..');
  const workflow = readFileSync(path.join(root, '.github/workflows/release-skill-archive.yml'), 'utf8');
  const step = workflow.match(/      - name: Write checksums\.json\n        run: \|\n([\s\S]*?)(?=\n      - name:)/);
  assert.ok(step, 'release workflow must write checksums before publishing');
  const sourceSha = 'a'.repeat(40);
  const releaseTag = `release-${sourceSha}-1792598742`;
  const values = {
    'steps.build.outputs.skill_md_sha': 'b'.repeat(64),
    'steps.build.outputs.skill_md_size': '123',
    'steps.build.outputs.archive_sha': 'c'.repeat(64),
    'steps.build.outputs.archive_size': '456',
    'steps.ids.outputs.source_sha': sourceSha,
    'steps.ids.outputs.built_at': '2026-10-21T16:05:42Z',
    'steps.ids.outputs.tag': releaseTag,
  };
  const script = step[1].replace(/^          /gm, '').replace(/\$\{\{ ([^}]+) \}\}/g, (_, key) => {
    assert.ok(Object.hasOwn(values, key), `unexpected release expression: ${key}`);
    return values[key];
  });
  const cwd = mkdtempSync(path.join(os.tmpdir(), 'display-release-metadata-'));
  t.after(() => rmSync(cwd, { recursive: true, force: true }));
  execFileSync('bash', ['-c', script], { cwd });
  const metadata = JSON.parse(readFileSync(path.join(cwd, 'checksums.json'), 'utf8'));
  assert.deepEqual(metadata, {
    skillMd: { sha256: 'b'.repeat(64), size: 123 },
    archive: { sha256: 'c'.repeat(64), size: 456 },
    sourceSha,
    builtAt: values['steps.ids.outputs.built_at'],
    releaseTag,
  });
});
