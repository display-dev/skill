import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, delimiter } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = fileURLToPath(new URL('../', import.meta.url));
const fixtures = join(root, 'tests/fixtures/comment-stream');
const script = join(root, 'display-dev/scripts/comments-stream.sh');

function runStream(scenario, resume = true, extraArgs = []) {
  const state = mkdtempSync(join(tmpdir(), 'display-comments-'));

  try {
    const home = join(state, 'home');
    const seen = join(state, 'seen');

    mkdirSync(home);

    if (resume) {
      writeFileSync(
        seen,
        '# dsp-comments-seen v1\nseen-comment\n',
      );
    }

    const env = {
      ...process.env,
      HOME: home,
      PATH: [fixtures, '/usr/bin', '/bin'].join(delimiter),
      TEST_STATE: state,
      TEST_SCENARIO: scenario,
      DISPLAYDEV_REPLY_SENTINEL: '[claude-bot] ',
    };

    delete env.DISPLAYDEV_API_KEY;

    const result = spawnSync('bash', [
      script,
      '--artifact', 'test-artifact',
      '--seen-file', seen,
      '--interval', '0',
      '--exit-after', '1',
      ...extraArgs,
    ], {
      env,
      encoding: 'utf8',
      timeout: 10000,
    });

    assert.ifError(result.error);

    return {
      ...result,
      calls: readFileSync(join(state, 'args'), 'utf8')
        .trim()
        .split('\n'),
      seen: readFileSync(seen, 'utf8'),
    };
  } finally {
    rmSync(state, { recursive: true, force: true });
  }
}

for (const scenario of [
  'malformed',
  'empty',
  'missing-data',
  'null-data',
  'multiple',
  'missing-id',
  'empty-id',
  'invalid-body',
  'network',
]) {
  test(`preserves cursor after ${scenario} response`, () => {
    const result = runStream(scenario);

    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.calls.length, 2);
    assert.doesNotMatch(result.calls[0], /--since/);
    assert.doesNotMatch(result.calls[1], /--since/);

    assert.deepEqual(JSON.parse(result.stdout), {
      id: 'new-comment',
      body: 'Reviewer feedback',
    });

    assert.match(result.seen, /new-comment/);
    assert.doesNotMatch(result.seen, /bot-comment/);
  });
}

test('advances cursor after a valid empty response', () => {
  const result = runStream('valid-empty');

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.calls.length, 2);
  assert.match(
    result.calls[1],
    /--since 2026-11-22T10:00:02Z/,
  );

  assert.equal(JSON.parse(result.stdout).id, 'new-comment');
});

for (const scenario of [
  'malformed',
  'empty',
  'missing-data',
  'null-data',
  'multiple',
  'missing-id',
  'empty-id',
]) {
  test(`rejects ${scenario} priming response`, () => {
    const result = runStream(scenario, false);

    assert.equal(result.status, 1);
    assert.equal(result.calls.length, 1);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /invalid priming response/);
    assert.equal(result.seen, '# dsp-comments-seen v1\n');
  });
}

test('primes existing roots and replies without emitting them', () => {
  const result = runStream('fresh-reply', false);

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.calls.length, 2);
  assert.deepEqual(JSON.parse(result.stdout), {
    id: 'new-reply',
    body: 'New feedback',
  });

  assert.match(result.seen, /^seen-comment$/m);
  assert.match(result.seen, /^old-reply$/m);
  assert.match(result.seen, /^new-reply$/m);
});

test('preserves an established cursor after a malformed poll', () => {
  const result = runStream('established-cursor', false);

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.calls.length, 3);
  assert.match(result.calls[1], /--since 2026-11-22T10:00:01Z/);
  assert.match(result.calls[2], /--since 2026-11-22T10:00:01Z/);
  assert.equal(JSON.parse(result.stdout).id, 'new-comment');
});

test('does not emit or record a partially invalid batch', () => {
  const result = runStream('partial-invalid');

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.calls.length, 2);
  assert.equal(JSON.parse(result.stdout).id, 'new-comment');
  assert.doesNotMatch(result.seen, /premature/);
});

test('allows sentinel filtering to be disabled', () => {
  const result = runStream('sentinel-disabled', true, [
    '--sentinel', '',
  ]);

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.calls.length, 1);
  assert.equal(JSON.parse(result.stdout).id, 'bot-comment');
});

test('priming only requires comment IDs', () => {
  const result = runStream('invalid-body', false);

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.calls.length, 2);
  assert.match(result.seen, /^comment-1$/m);
});
