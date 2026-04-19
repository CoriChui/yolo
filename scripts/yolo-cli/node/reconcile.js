#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { git } = require('./yolo');

function parseFrontmatter(file, field) {
  let inFm = false;
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    if (line === '---') { if (inFm) break; inFm = true; continue; }
    if (!inFm) continue;
    if (line.startsWith('##')) break;
    const m = line.match(new RegExp(`^${field}:\\s*(.*)`));
    if (m) return m[1].trim();
  }
  return '';
}

const args = process.argv.slice(2);
let fix = false, repo = '.', featureFile = '', branch = '';
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--fix' || args[i] === '--apply') { fix = true; continue; }
  if (args[i] === '--repo') { repo = args[++i]; continue; }
  if (args[i].startsWith('-')) { process.stderr.write(`Unknown option: ${args[i]}\n`); process.exit(1); }
  if (!featureFile) { featureFile = args[i]; continue; }
  if (!branch) { branch = args[i]; continue; }
}

// Unsafe state check
const gitDir = git('rev-parse --git-dir', repo);
if (gitDir) {
  const abs = path.isAbsolute(gitDir) ? gitDir : path.join(repo, gitDir);
  for (const [m, l] of [['rebase-merge','rebase'],['rebase-apply','rebase'],['MERGE_HEAD','merge'],['CHERRY_PICK_HEAD','cherry-pick'],['REVERT_HEAD','revert'],['BISECT_LOG','bisect']]) {
    if (fs.existsSync(path.join(abs, m))) { process.stderr.write(`Error: refusing to reconcile during ${l}\n`); process.exit(1); }
  }
}

if (!featureFile) { process.stderr.write('Usage: reconcile.js <feature-file> [<branch>] [--apply] [--repo <path>]\n'); process.exit(1); }
if (!branch) branch = parseFrontmatter(featureFile, 'branch');
if (!branch) { process.stderr.write('Error: no branch specified\n'); process.exit(1); }
if (!fs.existsSync(featureFile)) { process.stderr.write(`Error: file not found: ${featureFile}\n`); process.exit(1); }
featureFile = path.resolve(featureFile);

const start = Date.now();
const content = fs.readFileSync(featureFile, 'utf8');
const tasks = [];
let inPlan = false;

for (const line of content.split('\n')) {
  if (/^##\s+Plan/.test(line)) { inPlan = true; continue; }
  if (inPlan && /^##\s/.test(line)) break;
  if (!inPlan) continue;
  const m = line.match(/^(\d+)\.\s+\[([ xX])\]\s+(.*)/);
  if (!m) continue;
  const hm = m[3].match(/[—–-]+\s*([0-9a-f]{7,40})$/);
  tasks.push({ id: `task-${m[1]}`, num: m[1], checked: m[2] !== ' ', label: m[3], hash: hm ? hm[1] : '' });
}

let mainBranch = '';
for (const c of ['main', 'master']) { if (git(`rev-parse --verify ${c}`, repo)) { mainBranch = c; break; } }
const mergeBase = mainBranch
  ? (git(`merge-base ${mainBranch} ${branch}`, repo) || git('rev-list --max-parents=0 HEAD', repo).split('\n')[0])
  : git('rev-list --max-parents=0 HEAD', repo).split('\n')[0];

const gitCommits = {};
for (const line of git(`log ${mergeBase}..${branch} --oneline --grep=\\[task-\\|\\[fix-`, repo).split('\n').filter(Boolean)) {
  const [hash, ...rest] = line.split(' ');
  const m = rest.join(' ').match(/\[(task|fix)-(\d+)\]/);
  if (m && !gitCommits[`task-${m[2]}`]) gitCommits[`task-${m[2]}`] = { hash, msg: rest.join(' ') };
}

const drift = [], reconciled = {};
let completed = 0;
for (const t of tasks) {
  const gc = gitCommits[t.id];
  if (gc) {
    reconciled[t.id] = { checked: true, hash: gc.hash };
    completed++;
    if (!t.checked) drift.push(`DRIFT: ${t.id} is UNCHECKED in file but has commit ${gc.hash}`);
    if (t.hash && t.hash !== gc.hash) drift.push(`DRIFT: ${t.id} hash mismatch (${t.hash} vs ${gc.hash})`);
  } else {
    reconciled[t.id] = { checked: false, hash: '' };
    if (t.checked) drift.push(`DRIFT: ${t.id} is CHECKED but has NO commit`);
  }
}

const orphans = [];
for (const tid of Object.keys(gitCommits)) {
  if (!tasks.find(t => t.id === tid)) orphans.push(`ORPHAN: ${gitCommits[tid].hash} references ${tid} not in plan`);
}

// Derive step
let hasVer = false, verPassed = '';
let readingVer = false;
for (const line of content.split('\n')) {
  if (/^##\s+Verification/.test(line)) { readingVer = true; continue; }
  if (readingVer && /^##\s/.test(line)) break;
  if (readingVer) {
    if (line.replace(/\s/g, '') && !/\(Written by/i.test(line)) hasVer = true;
    const pm = line.match(/passed:\s*(true|false)/);
    if (pm) verPassed = pm[1];
  }
}

let isMerged = false;
if (mainBranch && tasks.length > 0 && tasks.some(t => t.checked))
  isMerged = !!git(`merge-base --is-ancestor ${branch} ${mainBranch}`, repo);

let step;
if (isMerged) step = 'done (merged)';
else if (!tasks.length) step = 'think (no plan tasks yet)';
else if (!completed) step = 'plan (plan exists, no tasks started)';
else if (completed < tasks.length) step = `do (${completed}/${tasks.length} tasks completed)`;
else if (hasVer) {
  if (verPassed === 'false') step = 'do-fix (verification failed)';
  else if (verPassed === 'true') step = 'ship (all tasks done, verified)';
  else step = 'check (verification incomplete)';
} else step = `check (all ${tasks.length} tasks done, needs verification)`;

// Output
const elapsed = ((Date.now() - start) / 1000).toFixed(0);
console.log('========================================');
console.log('  YOLO v2 Reconciliation Report');
console.log('========================================');
console.log(`\nFeature file: ${featureFile}\nBranch:       ${branch}\nElapsed:      ${elapsed}s`);
console.log('\n--- Current Step ---');
console.log(`  ${step}`);
console.log('\n--- Task Status ---');
console.log(`  ${'TASK'.padEnd(12)} ${'FILE'.padEnd(10)} ${'GIT'.padEnd(10)} LABEL`);
console.log(`  ${'----'.padEnd(12)} ${'----'.padEnd(10)} ${'---'.padEnd(10)} -----`);
for (const t of tasks) {
  const fs = t.checked ? '[x]' : '[ ]';
  const gs = gitCommits[t.id] ? gitCommits[t.id].hash : 'no commit';
  const lb = t.label.length > 50 ? t.label.slice(0, 47) + '...' : t.label;
  console.log(`  ${t.id.padEnd(12)} ${fs.padEnd(10)} ${gs.padEnd(10)} ${lb}`);
}

console.log('\n--- Drift Detection ---');
if (!drift.length && !orphans.length) console.log('  No drift detected. File matches git evidence.');
else { for (const d of [...drift, ...orphans]) console.log(`  ${d}`); console.log(`\n  Total drift items: ${drift.length + orphans.length}`); }

// Fix mode
if (fix && (drift.length || orphans.length)) {
  console.log('\n--- Fix Mode: Updating feature file ---');
  const out = [];
  let inP = false;
  for (const line of content.split('\n')) {
    if (/^##\s+Plan/.test(line)) { inP = true; out.push(line); continue; }
    if (inP && /^##\s/.test(line)) { inP = false; out.push(line); continue; }
    if (inP) {
      const m = line.match(/^(\d+)\.\s+\[([ xX])\]\s+(.*)/);
      if (m) {
        const tid = `task-${m[1]}`;
        const cl = m[3].replace(/\s*[—–-]+\s*[0-9a-f]{7,40}$/, '');
        out.push(reconciled[tid]?.checked ? `${m[1]}. [x] ${cl} — ${reconciled[tid].hash}` : `${m[1]}. [ ] ${cl}`);
        continue;
      }
    }
    out.push(line);
  }
  require('fs').writeFileSync(featureFile, out.join('\n'));
  console.log(`  Feature file updated: ${featureFile}`);
} else if (fix) {
  console.log('\n--- Fix Mode ---\n  No drift to fix.');
}

console.log('\nDone.');
if (!fix && (drift.length || orphans.length)) process.exit(2);
