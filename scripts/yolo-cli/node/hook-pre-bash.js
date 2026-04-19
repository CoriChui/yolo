#!/usr/bin/env node
'use strict';

const path = require('path');
const fs = require('fs');
const os = require('os');
const { execSync } = require('child_process');
const { parseStdin, getActiveFeature, isPathInScope, auditLog, git } = require('./yolo');

const input = parseStdin();
if (!input) {
  process.stderr.write('Blocked: YOLO hook failed to parse Bash tool input as JSON.\n');
  process.exit(2);
}

const command = input?.tool_input?.command || '';
if (!command) process.exit(0);

// ── 1. Destructive git operations ────────────────────────────────────
const BLOCKED = [
  /\bgit\s+push\b/, /\bgit\s+reset\s+--hard\b/, /\bgit\s+clean\s+-f/,
  /\bgit\s+checkout\s+\./, /\bgit\s+restore\s+\./, /\bgit\s+branch\s+-D\b/,
  /\bgit\s+push\s+--force\b/, /\bgit\s+push\s+-f\b/,
];
for (const re of BLOCKED) {
  if (re.test(command)) {
    process.stderr.write(`Blocked: '${re}' is not allowed in agent context.\n`);
    process.exit(2);
  }
}

// ── 2. Feature-file tamper protection ─────────────────────────────────
if (/\b(rm|mv|unlink|shred|truncate)\s[^;&|]*\.planning\/features\/[^/]+\/feature\.md/.test(command)) {
  process.stderr.write('Blocked: command tampers with a feature plan file.\n');
  process.exit(2);
}

// ── 3. Snapshot for post-bash delta check ─────────────────────────────
const repo = process.env.CLAUDE_PROJECT_DIR || process.cwd();
try {
  const porcelain = git('status --porcelain', repo);
  const snapFile = path.join(os.tmpdir(), `yolo-snap-${process.ppid || process.pid}.txt`);
  fs.writeFileSync(snapFile, porcelain, { mode: 0o600 });
} catch { /* best-effort */ }

// ── 4. Write-redirection scope gate ───────────────────────────────────
const slug = getActiveFeature(repo);
if (!slug) process.exit(0);

const featureFile = path.join(repo, '.planning', 'features', slug, 'feature.md');
if (!fs.existsSync(featureFile)) process.exit(0);

// Extract write targets from command. Node's regex is much more reliable
// than bash's grep chains.
const targets = new Set();

// Shell redirections: > file, >> file, &> file, n> file
for (const m of command.matchAll(/[12&]?>{1,2}\s*([^\s;&|<>]+)/g)) {
  const t = m[1].replace(/^["']|["']$/g, '');
  if (!/^&\d/.test(t)) targets.add(t); // Skip &1, &2 fd redirects
}

// sed -i: last non-flag token
if (/\bsed\s+.*-i/.test(command)) {
  const parts = command.replace(/.*\bsed\s+/, '').split(/\s+/);
  const last = parts[parts.length - 1];
  if (last && !last.startsWith('-')) targets.add(last);
}

// tee: first non-flag arg after tee
const teeMatch = command.match(/\btee(?:\s+-\w+)*\s+([^\s;&|]+)/);
if (teeMatch) targets.add(teeMatch[1]);

// cp/mv: last token in segment
for (const cmd of ['cp', 'mv']) {
  const re = new RegExp(`\\b${cmd}\\s+([^;&|]+)`);
  const m = command.match(re);
  if (m) {
    const tokens = m[1].trim().split(/\s+/).filter(t => !t.startsWith('-'));
    if (tokens.length > 0) targets.add(tokens[tokens.length - 1]);
  }
}

// git checkout <ref> -- <paths>
const checkoutMatch = command.match(/\bgit\s+(?:checkout|restore)\s+.*--\s+(.+?)(?:[;&|]|$)/);
if (checkoutMatch) {
  for (const t of checkoutMatch[1].split(/\s+/).filter(Boolean)) targets.add(t);
}

// Gate each target
for (let t of targets) {
  t = t.replace(/^["']|["']$/g, '');
  if (!t) continue;
  if (/^\/(tmp|dev|var\/tmp)\//.test(t)) continue;
  if (!isPathInScope(featureFile, t, repo)) {
    process.stderr.write(`YOLO bash gate: command writes to '${t}' outside plan scope for feature '${slug}'.\n`);
    if (process.env.YOLO_BYPASS === '1') {
      process.stderr.write('YOLO bash gate: bypass honored (YOLO_BYPASS=1)\n');
      auditLog(repo, 'bypass', 'pre-bash', slug, t, command.slice(0, 200));
      process.exit(0);
    }
    auditLog(repo, 'block', 'pre-bash', slug, t, command.slice(0, 200));
    process.exit(2);
  }
}

process.exit(0);
