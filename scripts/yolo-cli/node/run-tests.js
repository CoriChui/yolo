#!/usr/bin/env node
'use strict';

const { execSync } = require('child_process');
const fs = require('fs');

function parseFrontmatter(file, field) {
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  let inFm = false;
  for (const line of lines) {
    if (line === '---') { if (inFm) break; inFm = true; continue; }
    if (!inFm) continue;
    if (line.startsWith('##')) break;
    const m = line.match(new RegExp(`^${field}:\\s*(.*)`));
    if (m) return m[1].trim();
  }
  return '';
}

function parseJsonArray(raw) {
  if (!raw) return [];
  raw = raw.replace(/^\[/, '').replace(/\]$/, '').trim();
  if (!raw) return [];
  try { return JSON.parse(`[${raw}]`); } catch {}
  return raw.split(',').map(s => s.trim().replace(/^["']|["']$/g, '')).filter(Boolean);
}

const args = process.argv.slice(2);
let featureFile = '', workdir = '.', tailLines = 200;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--repo' || args[i] === '--workdir') { workdir = args[++i]; continue; }
  if (args[i] === '--tail') { tailLines = parseInt(args[++i], 10); continue; }
  if (args[i].startsWith('-')) { process.stderr.write(`Error: unknown arg '${args[i]}'\n`); process.exit(1); }
  if (!featureFile) featureFile = args[i];
}

if (!featureFile) { process.stderr.write('Usage: run-tests.js <feature-file> [--repo <path>] [--tail <N>]\n'); process.exit(1); }
if (!fs.existsSync(featureFile)) { process.stderr.write(`Error: file not found: ${featureFile}\n`); process.exit(1); }

const lintCmds = parseJsonArray(parseFrontmatter(featureFile, 'lint_commands'));
const testCmds = parseJsonArray(parseFrontmatter(featureFile, 'test_commands'));
let overall = 0;

function runCmd(label, cmd) {
  process.stdout.write(`=== ${label}: ${cmd} ===\n`);
  try {
    const out = execSync(cmd, { cwd: workdir, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], timeout: 300000 });
    const lines = out.split('\n');
    process.stdout.write(lines.length > tailLines ? `[output truncated to last ${tailLines} lines]\n` + lines.slice(-tailLines).join('\n') + '\n' : out);
    process.stdout.write('=== Exit code: 0 ===\n\n');
  } catch (e) {
    process.stdout.write((e.stdout || '') + (e.stderr || ''));
    process.stdout.write(`=== Exit code: ${e.status || 1} ===\n\n`);
    overall = 1;
  }
}

for (const cmd of lintCmds) runCmd('LINT', cmd);
for (const cmd of testCmds) runCmd('TEST', cmd);
process.exit(overall);
