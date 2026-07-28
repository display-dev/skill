#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { lstat, mkdir, readdir, readFile, realpath, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { gzipSync } from 'node:zlib';

const MAX_UNPACKED_BYTES = 10 * 1024 * 1024;
const ARCHIVE_NAME = 'display-dev.tar.gz';
const DIGEST_NAME = 'candidate-digest.json';

function fail(message) {
  throw new Error(message);
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (!['--source', '--output'].includes(flag) || !value) {
      fail('usage: build-candidate.mjs --source <local-skill-tree> --output <local-directory>');
    }
    args[flag.slice(2)] = value;
  }
  if (!args.source || !args.output) {
    fail('both --source and --output are required');
  }
  for (const [name, value] of Object.entries(args)) {
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(value)) {
      fail(`${name} must be a local path`);
    }
  }
  return args;
}

function writeOctal(buffer, offset, length, value) {
  const encoded = value.toString(8).padStart(length - 1, '0');
  if (encoded.length > length - 1) fail(`tar value does not fit: ${value}`);
  buffer.write(encoded, offset, length - 1, 'ascii');
  buffer[offset + length - 1] = 0;
}

function tarHeader(entry) {
  if (Buffer.byteLength(entry.name, 'utf8') > 100) {
    fail(`candidate path exceeds ustar name field: ${entry.name}`);
  }
  const header = Buffer.alloc(512);
  header.write(entry.name, 0, 100, 'utf8');
  writeOctal(header, 100, 8, entry.mode);
  writeOctal(header, 108, 8, 0);
  writeOctal(header, 116, 8, 0);
  writeOctal(header, 124, 12, entry.bytes.length);
  writeOctal(header, 136, 12, 0);
  header.fill(0x20, 148, 156);
  header[156] = '0'.charCodeAt(0);
  header.write('ustar\0', 257, 6, 'ascii');
  header.write('00', 263, 2, 'ascii');
  header.write('root', 265, 32, 'ascii');
  header.write('root', 297, 32, 'ascii');
  const checksum = header.reduce((sum, byte) => sum + byte, 0);
  const encodedChecksum = checksum.toString(8).padStart(6, '0');
  header.write(encodedChecksum, 148, 6, 'ascii');
  header[154] = 0;
  header[155] = 0x20;
  return header;
}

function buildTar(entries) {
  const chunks = [];
  for (const entry of entries) {
    chunks.push(tarHeader(entry), entry.bytes);
    const padding = (512 - (entry.bytes.length % 512)) % 512;
    if (padding) chunks.push(Buffer.alloc(padding));
  }
  chunks.push(Buffer.alloc(1024));
  return Buffer.concat(chunks);
}

async function collectDirectory(sourceRoot, directory) {
  const absolute = path.join(sourceRoot, directory);
  const dirStat = await lstat(absolute);
  if (!dirStat.isDirectory() || dirStat.isSymbolicLink()) {
    fail(`${directory} must be a real directory`);
  }
  const names = (await readdir(absolute)).sort();
  const entries = [];
  for (const basename of names) {
    if (basename === '.DS_Store') continue;
    const name = `${directory}/${basename}`;
    if (!/^(scripts|bin)\/[^/]+$/.test(name)) fail(`invalid candidate path: ${name}`);
    const absoluteFile = path.join(absolute, basename);
    const stat = await lstat(absoluteFile);
    if (!stat.isFile() || stat.isSymbolicLink()) fail(`candidate entry must be a regular file: ${name}`);
    entries.push({ name, mode: (stat.mode & 0o111) ? 0o755 : 0o644, bytes: await readFile(absoluteFile) });
  }
  return entries;
}

export async function buildCandidate(sourcePath, outputPath) {
  const sourceRoot = await realpath(sourcePath);
  await mkdir(outputPath, { recursive: true });
  const outputRoot = await realpath(outputPath);
  if (outputRoot === sourceRoot || outputRoot.startsWith(`${sourceRoot}${path.sep}`)) {
    fail('output must be outside the canonical skill tree');
  }

  const skillPath = path.join(sourceRoot, 'SKILL.md');
  const skillStat = await lstat(skillPath);
  if (!skillStat.isFile() || skillStat.isSymbolicLink()) fail('SKILL.md must be a regular file');
  const entries = [
    { name: 'SKILL.md', mode: 0o644, bytes: await readFile(skillPath) },
    ...(await collectDirectory(sourceRoot, 'scripts')),
    ...(await collectDirectory(sourceRoot, 'bin')),
  ].sort((left, right) => Buffer.compare(Buffer.from(left.name), Buffer.from(right.name)));

  const unpackedSize = entries.reduce((sum, entry) => sum + entry.bytes.length, 0);
  if (unpackedSize > MAX_UNPACKED_BYTES) fail(`candidate exceeds ${MAX_UNPACKED_BYTES} unpacked bytes`);
  for (const entry of entries) {
    if (entry.name.startsWith('/') || entry.name.startsWith('./') || entry.name.includes('..')) {
      fail(`unsafe candidate path: ${entry.name}`);
    }
  }

  // Node's gzip wrapper writes a zero MTIME header, so identical tar bytes
  // produce identical gzip bytes without a host-clock input.
  const archive = gzipSync(buildTar(entries), { level: 9 });
  const sha256 = createHash('sha256').update(archive).digest('hex');
  const digest = `${JSON.stringify({ archive: { sha256, size: archive.length } }, null, 2)}\n`;
  await writeFile(path.join(outputRoot, ARCHIVE_NAME), archive, { flag: 'wx' });
  await writeFile(path.join(outputRoot, DIGEST_NAME), digest, { flag: 'wx' });
  return { archive, digest: JSON.parse(digest), entries };
}

if (process.argv[1] && import.meta.url === pathToFileURL(await realpath(process.argv[1])).href) {
  const args = parseArgs(process.argv.slice(2));
  buildCandidate(args.source, args.output).catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
