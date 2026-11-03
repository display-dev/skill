import assert from 'node:assert/strict';
import { cp, mkdtemp, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { buildStandalone } from '../bin/build-standalone.mjs';

const canonical = path.resolve(import.meta.dirname, '../display-dev');

async function fixture(t) {
  const temp = await mkdtemp(path.join(os.tmpdir(), 'display-dev-standalone-'));
  t.after(() => rm(temp, { recursive: true, force: true }));
  const source = path.join(temp, 'source');
  await cp(canonical, source, { recursive: true });
  return source;
}

test('standalone preserves frontmatter and includes exact reference bytes in stable path order', async () => {
  const original = await readFile(path.join(canonical, 'SKILL.md'), 'utf8');
  const built = await buildStandalone(canonical);
  assert.deepEqual(built, await buildStandalone(canonical));
  const text = built.toString();
  const frontmatter = original.match(/^---\n[\s\S]*?\n---\n/)[0];
  assert.ok(text.startsWith(frontmatter));
  assert.ok(text.includes(original.slice(frontmatter.length)));
  let previous = -1;
  for (const file of ['email-domains.md', 'staged-upload.md']) {
    const content = await readFile(path.join(canonical, 'references', file), 'utf8');
    const start = text.indexOf(`\n\n## references/${file}\n\n${content}`);
    assert.ok(start > previous);
    previous = start;
  }
});

test('no-reference standalone remains byte-identical', async (t) => {
  const source = await fixture(t);
  await rm(path.join(source, 'references'), { recursive: true });
  const original = Buffer.from('---\r\nname: example\r\ndescription: Example\r\n---\r\n\r\nUnchanged.\r\n');
  await writeFile(path.join(source, 'SKILL.md'), original);
  assert.deepEqual(await buildStandalone(source), original);
});

test('missing, unrouted, and unsafe reference paths fail generation', async (t) => {
  const source = await fixture(t);
  await rm(path.join(source, 'references', 'staged-upload.md'));
  await assert.rejects(buildStandalone(source), /must match/);
  await writeFile(path.join(source, 'references', 'staged-upload.md'), 'restored');
  await writeFile(path.join(source, 'references', 'unrouted.md'), 'would be omitted');
  await assert.rejects(buildStandalone(source), /must match/);
  await rm(path.join(source, 'references', 'unrouted.md'));
  const skill = await readFile(path.join(source, 'SKILL.md'), 'utf8');
  await writeFile(path.join(source, 'SKILL.md'), `${skill}\n[bad](references/../private.md)\n`);
  await assert.rejects(buildStandalone(source), /invalid reference path/);
});

test('linked references are rejected rather than read outside the skill', async (t) => {
  const source = await fixture(t);
  const file = path.join(source, 'references', 'staged-upload.md');
  await rm(file);
  await symlink('../SKILL.md', file);
  await assert.rejects(buildStandalone(source), /regular file/);
  await rm(path.join(source, 'references'), { recursive: true });
  await symlink('scripts', path.join(source, 'references'));
  await assert.rejects(buildStandalone(source), /real directory/);
});
