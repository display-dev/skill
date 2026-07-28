import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { chmod, cp, mkdtemp, mkdir, readFile, readdir, symlink, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { promisify } from 'node:util';
import { gunzipSync } from 'node:zlib';

import { buildCandidate } from '../bin/build-candidate.mjs';

const repositoryRoot = path.resolve(import.meta.dirname, '..');
const canonicalRoot = path.join(repositoryRoot, 'display-dev');
const execFileAsync = promisify(execFile);

function parseTar(bytes) {
  const entries = [];
  for (let offset = 0; offset + 512 <= bytes.length;) {
    const header = bytes.subarray(offset, offset + 512);
    if (header.every((byte) => byte === 0)) break;
    const name = header.subarray(0, 100).toString('utf8').replace(/\0.*$/, '');
    const mode = Number.parseInt(header.subarray(100, 108).toString('ascii').replace(/\0.*$/, '').trim(), 8);
    const size = Number.parseInt(header.subarray(124, 136).toString('ascii').replace(/\0.*$/, '').trim(), 8);
    const storedChecksum = Number.parseInt(header.subarray(148, 156).toString('ascii').replace(/\0.*$/, '').trim(), 8);
    const checksumHeader = Buffer.from(header);
    checksumHeader.fill(0x20, 148, 156);
    assert.equal(checksumHeader.reduce((sum, byte) => sum + byte, 0), storedChecksum);
    assert.deepEqual(header.subarray(257, 265), Buffer.from('ustar\0' + '00', 'ascii'));
    const type = String.fromCharCode(header[156]);
    offset += 512;
    const file = bytes.subarray(offset, offset + size);
    entries.push({ name, mode, type, bytes: Buffer.from(file) });
    offset += size + ((512 - (size % 512)) % 512);
  }
  return entries;
}

async function expectedEntries(root) {
  const names = ['SKILL.md'];
  for (const directory of ['scripts', 'bin']) {
    for (const basename of (await readdir(path.join(root, directory))).sort()) {
      if (basename !== '.DS_Store') names.push(`${directory}/${basename}`);
    }
  }
  return Promise.all(names.sort().map(async (name) => {
    const filePath = path.join(root, name);
    const mode = name === 'SKILL.md' || name.endsWith('.LICENSE') ? 0o644 : 0o755;
    return { name, mode, bytes: await readFile(filePath) };
  }));
}

test('builds a deterministic complete archive with exact bytes, modes, and digest', async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), 'display-dev-candidate-'));
  const first = path.join(temp, 'first');
  const second = path.join(temp, 'second');
  const one = await buildCandidate(canonicalRoot, first);
  const two = await buildCandidate(canonicalRoot, second);
  assert.deepEqual(one.archive, two.archive);
  assert.deepEqual(one.archive.subarray(4, 8), Buffer.alloc(4));

  const parsed = parseTar(gunzipSync(one.archive));
  const expected = await expectedEntries(canonicalRoot);
  assert.deepEqual(parsed.map(({ name, mode, type }) => ({ name, mode, type })), expected.map(({ name, mode }) => ({ name, mode, type: '0' })));
  for (const entry of parsed) {
    assert.deepEqual(entry.bytes, expected.find(({ name }) => name === entry.name).bytes);
    assert.match(entry.name, /^(SKILL\.md|scripts\/[^/]+|bin\/[^/]+)$/);
  }
  assert.ok(parsed.reduce((sum, entry) => sum + entry.bytes.length, 0) <= 10 * 1024 * 1024);

  const digest = JSON.parse(await readFile(path.join(first, 'candidate-digest.json'), 'utf8'));
  assert.equal(digest.archive.size, one.archive.length);
  assert.equal(digest.archive.sha256, createHash('sha256').update(one.archive).digest('hex'));
});

test('rejects links and nested entries instead of archiving unsafe entry types or paths', async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), 'display-dev-candidate-invalid-'));
  const source = path.join(temp, 'source');
  await cp(canonicalRoot, source, { recursive: true });
  await symlink('publish.sh', path.join(source, 'scripts', 'linked.sh'));
  await assert.rejects(buildCandidate(source, path.join(temp, 'linked-output')), /regular file/);

  await cp(canonicalRoot, path.join(temp, 'nested-source'), { recursive: true });
  const nestedSource = path.join(temp, 'nested-source');
  await mkdir(path.join(nestedSource, 'bin', 'nested'));
  await writeFile(path.join(nestedSource, 'bin', 'nested', 'tool'), 'unsafe');
  await assert.rejects(buildCandidate(nestedSource, path.join(temp, 'nested-output')), /regular file/);
});

test('normalizes canonical executable and regular-file modes', async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), 'display-dev-candidate-mode-'));
  const source = path.join(temp, 'source');
  await cp(canonicalRoot, source, { recursive: true });
  await chmod(path.join(source, 'SKILL.md'), 0o600);
  await chmod(path.join(source, 'scripts', 'publish.sh'), 0o700);
  await chmod(path.join(source, 'bin', 'jq-linux-amd64'), 0o711);
  await chmod(path.join(source, 'bin', 'jq.LICENSE'), 0o640);
  const result = await buildCandidate(source, path.join(temp, 'output'));
  const parsed = parseTar(gunzipSync(result.archive));
  assert.equal(parsed.find(({ name }) => name === 'SKILL.md').mode, 0o644);
  assert.equal(parsed.find(({ name }) => name === 'scripts/publish.sh').mode, 0o755);
  assert.equal(parsed.find(({ name }) => name === 'bin/jq-linux-amd64').mode, 0o755);
  assert.equal(parsed.find(({ name }) => name === 'bin/jq.LICENSE').mode, 0o644);
});

test('rejects names that do not fit the ustar name field', async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), 'display-dev-candidate-long-name-'));
  const source = path.join(temp, 'source');
  await cp(canonicalRoot, source, { recursive: true });
  await writeFile(path.join(source, 'scripts', `${'x'.repeat(100)}.sh`), 'unsafe');
  await assert.rejects(
    buildCandidate(source, path.join(temp, 'output')),
    /exceeds ustar name field/,
  );
});

test('runs as a CLI from a path requiring URL encoding', async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), 'display dev candidate '));
  const script = path.join(temp, 'builder copy.mjs');
  const output = path.join(temp, 'output');
  await cp(path.join(repositoryRoot, 'bin', 'build-candidate.mjs'), script);
  await execFileAsync(process.execPath, [script, '--source', canonicalRoot, '--output', output]);
  assert.ok((await readFile(path.join(output, 'display-dev.tar.gz'))).length > 0);
  assert.equal(JSON.parse(await readFile(path.join(output, 'candidate-digest.json'), 'utf8')).archive.sha256.length, 64);
});
