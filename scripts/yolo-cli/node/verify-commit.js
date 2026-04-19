#!/usr/bin/env node
'use strict';

const { git } = require('./yolo');

const TEST_FILE_RE = /(\.(test|spec)\.|_test\.|(^|\/)test_|__tests__\/|tests\/)/;
const TEST_PATTERNS = /(test\(|it\(|describe\(|def test_|#\[test\]|@Test|func Test)/g;
const SKIP_PATTERNS = /\.(skip|only)\b|xit\(|xdescribe\(|@pytest\.mark\.skip|@unittest\.skip|@disabled|@Disabled|#\[ignore\]/;

const args = process.argv.slice(2);
const taskId = args[0], filesClaimed = args[1] || '';
let repo = '.', commitHash = '', branch = '', allowTestReduction = false;

for (let i = 2; i < args.length; i++) {
  if (args[i] === '--repo') { repo = args[++i]; continue; }
  if (args[i] === '--commit-hash') { commitHash = args[++i]; continue; }
  if (args[i] === '--branch') { branch = args[++i]; continue; }
  if (args[i] === '--allow-test-reduction') { allowTestReduction = true; continue; }
}

if (!taskId) { process.stderr.write('Usage: verify-commit.js <task-id> <files-changed> [--repo <path>]\n'); process.exit(1); }

if (!commitHash) {
  commitHash = git(`log -1 --format=%H --grep=\\[${taskId}\\]\\|\\[fix-${taskId.replace('task-', '')}\\] ${branch}`, repo);
}
if (!commitHash) { process.stderr.write(`Error: no commit found matching [${taskId}]\n`); process.exit(1); }

const actualFiles = git(`diff-tree --no-commit-id --name-only -r ${commitHash}`, repo).split('\n').filter(Boolean);
const claimedFiles = filesClaimed ? filesClaimed.split(',').map(f => f.trim()).filter(Boolean) : [];
const warnings = [];

if (actualFiles.length === 0) warnings.push(`thin_commit:0 files changed in ${commitHash}`);

for (const f of actualFiles) { if (!claimedFiles.includes(f)) warnings.push(`unexpected_file:${f}`); }
for (const f of claimedFiles) { if (!actualFiles.includes(f)) warnings.push(`claimed_not_changed:${f}`); }

if (!allowTestReduction) {
  for (const f of actualFiles) {
    if (!TEST_FILE_RE.test(f)) continue;
    const prev = git(`show ${commitHash}~1:${f}`, repo);
    const curr = git(`show ${commitHash}:${f}`, repo);
    const pc = (prev.match(TEST_PATTERNS) || []).length; TEST_PATTERNS.lastIndex = 0;
    const cc = (curr.match(TEST_PATTERNS) || []).length; TEST_PATTERNS.lastIndex = 0;
    if (cc < pc) warnings.push(`test_count_decreased:${f}:${pc}>${cc}`);
    const diff = git(`diff ${commitHash}~1 ${commitHash} -- ${f}`, repo);
    if (diff.split('\n').filter(l => l.startsWith('+')).some(l => SKIP_PATTERNS.test(l)))
      warnings.push(`skip_marker_added:${f}`);
  }
}

if (warnings.length > 0) {
  process.stderr.write(`verify-commit: ${warnings.length} warning(s) for ${taskId} (${commitHash}):\n`);
  for (const w of warnings) { const [t, ...d] = w.split(':'); process.stderr.write(`  WARNING: ${t} — ${d.join(':')}\n`); }
  process.exit(1);
}
process.stdout.write(`verify-commit: ${taskId} (${commitHash}) verified — ${actualFiles.length} file(s), no issues.\n`);
