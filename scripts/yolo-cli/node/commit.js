#!/usr/bin/env node
'use strict';

const { execSync } = require('child_process');
const { git, getActiveFeature } = require('./yolo');

const TEST_FILE_RE = /(\.(test|spec)\.|_test\.|(^|\/)test_|__tests__\/|tests\/)/;
const TEST_PATTERNS = /(test\(|it\(|describe\(|def test_|#\[test\]|@Test|func Test|class Test)/g;
const SKIP_PATTERNS = /\.(skip|only)\b|xit\(|xdescribe\(|@pytest\.mark\.skip|@unittest\.skip|@disabled|@Disabled|#\[ignore\]/;

const args = process.argv.slice(2);
const prefixType = args[0];
if (!prefixType || !['task', 'fix', 'wip', 'revert', 'squash'].includes(prefixType)) {
  process.stderr.write(`Error: prefix type must be task|fix|wip|revert|squash, got '${prefixType || ''}'\n`);
  process.exit(1);
}

let repo = '.', allowTestReduction = false, stageAll = false, jsonOutput = false;
const positional = [];
for (let i = 1; i < args.length; i++) {
  if (args[i] === '--repo') { repo = args[++i]; continue; }
  if (args[i] === '--allow-test-reduction') { allowTestReduction = true; continue; }
  if (args[i] === '--stage') { stageAll = true; continue; }
  if (args[i] === '--json') { jsonOutput = true; continue; }
  positional.push(args[i]);
}

let taskNum, msg, fullPrefix;
if (prefixType === 'task' || prefixType === 'fix') {
  taskNum = positional[0]; msg = positional[1];
  if (!taskNum || !/^\d+$/.test(taskNum)) { process.stderr.write(`Error: ${prefixType} requires a numeric task number\n`); process.exit(1); }
  if (!msg) { process.stderr.write(`Error: ${prefixType} requires a message\n`); process.exit(1); }
  fullPrefix = `[${prefixType}-${taskNum}]`;
} else if (prefixType === 'wip') {
  msg = positional[0] || 'Parking feature'; fullPrefix = '[wip]';
} else if (prefixType === 'revert') {
  msg = positional[0] || 'revert'; fullPrefix = '[revert]';
} else {
  msg = positional[0];
  if (!msg) { process.stderr.write("Error: squash requires a message\n"); process.exit(1); }
  fullPrefix = '[squash]';
}

let commitMsg = `${fullPrefix} ${msg}`;

// Trailers
const slug = getActiveFeature(repo);
const phaseMap = { task: 'do', fix: 'do', wip: 'wip', revert: 'revert', squash: 'ship' };
const phase = phaseMap[prefixType] || '';

if (slug && phase) {
  try {
    commitMsg = execSync('git interpret-trailers --if-exists replace ' +
      `--trailer "YOLO-Feature: ${slug}" --trailer "YOLO-Phase: ${phase}"`,
      { input: commitMsg, cwd: repo, encoding: 'utf8' }).trim();
  } catch {}
} else if (phase && prefixType === 'squash') {
  try {
    commitMsg = execSync(`git interpret-trailers --if-exists replace --trailer "YOLO-Phase: ${phase}"`,
      { input: commitMsg, cwd: repo, encoding: 'utf8' }).trim();
  } catch {}
}

// Squash guard
if (prefixType === 'squash') {
  const branch = git('rev-parse --abbrev-ref HEAD', repo);
  if (branch !== 'main' && branch !== 'master') {
    process.stderr.write(`Error: squash commits only allowed on main/master (current: ${branch})\n`);
    process.exit(1);
  }
}

// Stage
if (stageAll) { try { execSync('git add -A', { cwd: repo, stdio: 'pipe' }); } catch {} }

// Test integrity
const warnings = [];
if ((prefixType === 'task' || prefixType === 'fix') && !allowTestReduction) {
  const deleted = git('diff --cached --name-only --diff-filter=D', repo).split('\n').filter(f => f && TEST_FILE_RE.test(f));
  for (const f of deleted) warnings.push(`test_file_deleted:${f}`);

  const testFiles = git('diff --cached --name-only --diff-filter=ACMR', repo).split('\n').filter(f => f && TEST_FILE_RE.test(f));
  if (testFiles.length > 0) {
    let headTotal = 0, stagedTotal = 0;
    for (const tf of testFiles) {
      const h = git(`show HEAD:${tf}`, repo); const s = git(`show :${tf}`, repo);
      headTotal += (h.match(TEST_PATTERNS) || []).length; TEST_PATTERNS.lastIndex = 0;
      stagedTotal += (s.match(TEST_PATTERNS) || []).length; TEST_PATTERNS.lastIndex = 0;
    }
    if (stagedTotal < headTotal) warnings.push(`test_count_decreased:${headTotal}>${stagedTotal}`);
    const diff = git(`diff --cached -- ${testFiles.join(' ')}`, repo);
    const skipCount = diff.split('\n').filter(l => l.startsWith('+') && SKIP_PATTERNS.test(l)).length;
    if (skipCount > 0) warnings.push(`skip_marker_added:${skipCount} lines`);
  }
}

// Commit
try {
  execSync(`git commit -m ${JSON.stringify(commitMsg)}`, { cwd: repo, stdio: 'pipe' });
} catch (e) {
  process.stderr.write(`Error: git commit failed\n${e.stderr || e.message}\n`);
  process.exit(1);
}

// Report
if (jsonOutput) {
  const w = warnings.map(w => { const [t, ...d] = w.split(':'); return { type: t, detail: d.join(':') }; });
  process.stdout.write(JSON.stringify({ committed: true, warnings: w, errors: [] }));
} else {
  for (const w of warnings) {
    const [t, ...d] = w.split(':');
    process.stderr.write(`WARNING: ${t} — ${d.join(':')}\n`);
  }
}
