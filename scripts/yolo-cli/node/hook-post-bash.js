#!/usr/bin/env node
'use strict';

const path = require('path');
const fs = require('fs');
const os = require('os');
const { execSync } = require('child_process');
const { getActiveFeature, isPathInScope, auditLog, git } = require('./yolo');

const repo = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const slug = getActiveFeature(repo);
if (!slug) process.exit(0);

const featureFile = path.join(repo, '.planning', 'features', slug, 'feature.md');
if (!fs.existsSync(featureFile)) {
  // Feature file missing on a feature branch = tamper. Fail closed.
  process.stderr.write(`YOLO post-bash: feature file for '${slug}' is missing — blocking.\n`);
  auditLog(repo, 'block', 'post-bash', slug, 'feature.md missing', '');
  process.exit(2);
}

if (process.env.YOLO_BYPASS === '1') process.exit(0);

// ── Read pre-command snapshot ─────────────────────────────────────────
const snapFile = path.join(os.tmpdir(), `yolo-snap-${process.ppid || process.pid}.txt`);
if (!fs.existsSync(snapFile)) process.exit(0); // No snapshot — skip

let snapshot;
try {
  snapshot = fs.readFileSync(snapFile, 'utf8');
  fs.unlinkSync(snapFile); // One-shot consumption
} catch { process.exit(0); }

// ── Compute delta ────────────────────────────────────────────────────
const current = git('status --porcelain', repo);
const snapLines = new Set(snapshot.split('\n').filter(Boolean));
const deltaLines = current.split('\n').filter(l => l && !snapLines.has(l));

if (deltaLines.length === 0) process.exit(0);

// ── Check scope of each delta path ───────────────────────────────────
const outOfScope = [];
const revertActions = [];

for (const line of deltaLines) {
  const xy = line.slice(0, 2);
  let pathPart = line.slice(3);
  // Handle renames: "orig -> new"
  if (pathPart.includes(' -> ')) pathPart = pathPart.split(' -> ')[1];
  pathPart = pathPart.replace(/^"|"$/g, '');

  if (isPathInScope(featureFile, pathPart, repo)) continue;

  outOfScope.push(pathPart);
  if (xy === '??' || xy === 'A ' || xy === 'AM' || xy === 'AD') {
    revertActions.push({ kind: 'untracked', path: pathPart });
  } else if (xy === 'D ' || xy === ' D') {
    revertActions.push({ kind: 'restore', path: pathPart });
  } else {
    revertActions.push({ kind: 'checkout', path: pathPart });
  }
}

if (outOfScope.length === 0) process.exit(0);

// ── Auto-revert (default ON) ─────────────────────────────────────────
const doRevert = process.env.YOLO_POST_BASH_REVERT !== '0';

if (doRevert) {
  for (const action of revertActions) {
    try {
      if (action.kind === 'untracked') {
        const full = path.join(repo, action.path);
        if (fs.existsSync(full)) fs.unlinkSync(full);
        try { execSync(`git -C "${repo}" rm -f --cached -- "${action.path}"`, { stdio: 'pipe' }); } catch {}
      } else {
        execSync(`git -C "${repo}" checkout HEAD -- "${action.path}"`, { stdio: 'pipe' });
      }
    } catch { /* best effort */ }
  }
}

// ── Report ───────────────────────────────────────────────────────────
const verb = doRevert ? 'reverted' : 'detected';
process.stderr.write(`YOLO post-bash: ${verb} out-of-scope changes for feature '${slug}'.\n\n`);
process.stderr.write('Out-of-scope paths:\n');
for (const p of outOfScope) process.stderr.write(`  - ${p}\n`);
process.stderr.write('\n');

for (const p of outOfScope) {
  auditLog(repo, doRevert ? 'revert' : 'report', 'post-bash', slug, p, '');
}

process.exit(2);
