#!/usr/bin/env node
'use strict';

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { getActiveFeature, parseTrailer, getCurrentPhase, isPathInScope, normalizePath, auditLog } = require('./yolo');

let pass = 0, fail = 0;

function assert(label, expected, actual) {
  if (expected === actual) { console.log(`  PASS: ${label}`); pass++; }
  else { console.log(`  FAIL: ${label}\n    expected: '${expected}'\n    actual:   '${actual}'`); fail++; }
}

function assertBool(label, expected, actual) {
  if (expected === actual) { console.log(`  PASS: ${label}`); pass++; }
  else { console.log(`  FAIL: ${label} — expected ${expected}, got ${actual}`); fail++; }
}

// ── Fixture ─────────────────────────────────────────────────────────
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'yolo-test-'));
process.on('exit', () => { try { execSync(`rm -rf "${tmp}"`); } catch {} });

const repo = path.join(tmp, 'repo');
fs.mkdirSync(path.join(repo, '.planning', 'features', 'auth'), { recursive: true });
fs.mkdirSync(path.join(repo, 'src'), { recursive: true });
execSync('git init -q -b main', { cwd: repo });
execSync('git config user.email "t@t.t"', { cwd: repo });
execSync('git config user.name "t"', { cwd: repo });

fs.writeFileSync(path.join(repo, '.planning', 'features', 'auth', 'feature.md'), `---
branch: feature/auth
---

## Plan
1. [ ] Add login module
  - files: src/login.ts, src/login.test.ts, "src/with space.ts", src/service/
  - test: none

2. [ ] Wire app
  - files: src/app.ts
  - test: none
`);

fs.writeFileSync(path.join(repo, 'seed.txt'), 'seed');
execSync('git add . && git commit -q -m seed', { cwd: repo });
execSync('git checkout -q -b feature/auth', { cwd: repo });

// ── getActiveFeature ─────────────────────────────────────────────────
console.log('=== getActiveFeature ===');
assert('on feature/auth returns slug', 'auth', getActiveFeature(repo));
execSync('git checkout -q main', { cwd: repo });
assert('on main returns null', null, getActiveFeature(repo));
execSync('git checkout -q -b feature/group/nested', { cwd: repo });
assert('nested slug works', 'group/nested', getActiveFeature(repo));
execSync('git checkout -q feature/auth', { cwd: repo });

// ── parseTrailer ─────────────────────────────────────────────────────
console.log('=== parseTrailer ===');
assert('missing trailer returns null', null, parseTrailer(repo, 'HEAD', 'YOLO-Phase'));

fs.writeFileSync(path.join(repo, 'work.txt'), 'x');
execSync('git add work.txt', { cwd: repo });
execSync(`git commit -q -m "[task-1] work\n\nYOLO-Feature: auth\nYOLO-Phase: do"`, { cwd: repo });

assert('extracts YOLO-Feature', 'auth', parseTrailer(repo, 'HEAD', 'YOLO-Feature'));
assert('extracts YOLO-Phase', 'do', parseTrailer(repo, 'HEAD', 'YOLO-Phase'));
assert('missing field returns null', null, parseTrailer(repo, 'HEAD', 'Nonexistent'));

// ── getCurrentPhase ──────────────────────────────────────────────────
console.log('=== getCurrentPhase ===');
assert('returns latest phase', 'do', getCurrentPhase(repo));

// New branch inherits commits but different slug → no match
execSync('git checkout -q -b feature/other', { cwd: repo });
assert('different feature returns empty (no matching trailer)', '', getCurrentPhase(repo));
execSync('git checkout -q feature/auth', { cwd: repo });

// ── isPathInScope ────────────────────────────────────────────────────
console.log('=== isPathInScope ===');
const ff = path.join(repo, '.planning', 'features', 'auth', 'feature.md');

assertBool('in-scope: src/login.ts', true, isPathInScope(ff, 'src/login.ts', repo));
assertBool('in-scope: src/app.ts', true, isPathInScope(ff, 'src/app.ts', repo));
assertBool('in-scope: .planning path', true, isPathInScope(ff, '.planning/anything.md', repo));
assertBool('out-of-scope: src/unrelated.ts', false, isPathInScope(ff, 'src/unrelated.ts', repo));

// Directory prefix
assertBool('dir prefix: src/service/login.ts', true, isPathInScope(ff, 'src/service/login.ts', repo));
assertBool('file-not-dir: src/auth/x.ts (no dir match for src/login.ts)', false, isPathInScope(ff, 'src/auth/x.ts', repo));

// Quoted entry with space
assertBool('quoted entry with space', true, isPathInScope(ff, 'src/with space.ts', repo));

// Absolute path inside repo
assertBool('absolute in-repo path', true, isPathInScope(ff, path.join(repo, 'src/login.ts'), repo));

// Absolute path OUTSIDE repo (C2 regression)
assertBool('outside-repo absolute path blocked', false, isPathInScope(ff, '/Users/evil/src/login.ts', repo));

// .. escape
assertBool('.. escape blocked', false, isPathInScope(ff, '../../etc/passwd', repo));

// No feature file
assertBool('no feature file + non-planning → false', false, isPathInScope(null, 'src/x.ts', repo));
assertBool('no feature file + .planning → true', true, isPathInScope(null, '.planning/x.md', repo));

// Symlink test (if possible)
try {
  const realTarget = path.join(repo, 'src', 'real-outside.ts');
  fs.writeFileSync(path.join(tmp, 'outside.txt'), 'outside');
  fs.symlinkSync(path.join(tmp, 'outside.txt'), realTarget);
  assertBool('symlink to outside repo blocked', false, isPathInScope(ff, 'src/real-outside.ts', repo));
  fs.unlinkSync(realTarget);
} catch (e) {
  console.log(`  SKIP: symlink test (${e.message})`);
}

// ── auditLog ─────────────────────────────────────────────────────────
console.log('=== auditLog ===');
const auditRepo = path.join(tmp, 'audit');
fs.mkdirSync(auditRepo, { recursive: true });
auditLog(auditRepo, 'block', 'pre-write', 'auth', 'src/x.ts', 'Edit');
auditLog(auditRepo, 'bypass', 'pre-bash', 'auth', 'src/y.ts', 'echo');

const logFile = path.join(auditRepo, '.planning', '.audit.log');
assertBool('audit log created', true, fs.existsSync(logFile));
const lines = fs.readFileSync(logFile, 'utf8').trim().split('\n');
assert('audit log has 2 lines', '2', String(lines.length));
assertBool('line has 6 tab fields', true, lines[0].split('\t').length === 6);
assertBool('block event recorded', true, lines[0].includes('block\tpre-write\tauth'));
assertBool('bypass event recorded', true, lines[1].includes('bypass\tpre-bash\tauth'));

// ── Summary ─────────────────────────────────────────────────────────
console.log(`\n=== Results: ${pass} passed, ${fail} failed ===`);
process.exit(fail > 0 ? 1 : 0);
