#!/usr/bin/env node

import { lstat, readFile, readdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

export async function buildStandalone(sourceRoot) {
  const original = await readFile(path.join(sourceRoot, 'SKILL.md'));
  const skill = original.toString('utf8');
  const routes = [...new Set([...skill.matchAll(/\]\((references\/[^)]+)\)/g)].map((match) => match[1]))].sort();
  const referenceRoot = path.join(sourceRoot, 'references');
  let names = [];
  try {
    const info = await lstat(referenceRoot);
    if (!info.isDirectory()) throw new Error('references must be a real directory');
    names = (await readdir(referenceRoot)).filter((name) => name !== '.DS_Store').sort();
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  for (const route of routes) {
    if (!/^references\/[a-z0-9-]+\.md$/.test(route)) throw new Error(`invalid reference path: ${route}`);
  }
  if (JSON.stringify(names.map((name) => `references/${name}`)) !== JSON.stringify(routes)) {
    throw new Error('reference files must match the paths routed from SKILL.md');
  }
  if (!routes.length) return original;

  const frontmatter = skill.match(/^---\r?\n[\s\S]*?\r?\n---\r?\n/);
  if (!frontmatter) throw new Error('SKILL.md is missing YAML frontmatter');
  const notice = '\nThis standalone file includes reference documents in appended sections labeled\n'+
    'with their exact paths. When an instruction asks you to read a reference, use\n'+
    'that section instead of opening a sibling file.\n';
  let output = frontmatter[0] + notice + skill.slice(frontmatter[0].length);
  for (const route of routes) {
    const file = path.join(sourceRoot, route);
    if (!(await lstat(file)).isFile()) throw new Error(`reference must be a regular file: ${route}`);
    output += `\n\n## ${route}\n\n${await readFile(file, 'utf8')}`;
  }
  return Buffer.from(output);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const [source, output, ...extra] = process.argv.slice(2);
  if (!source || !output || extra.length) throw new Error('usage: build-standalone.mjs <skill-tree> <output-file>');
  await writeFile(output, await buildStandalone(source));
}
