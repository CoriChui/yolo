#!/usr/bin/env node
'use strict';

const path = require('path');
const { parseStdin, getActiveFeature, isPathInScope, auditLog } = require('./yolo');

const input = parseStdin();
if (!input) {
  // Failed to parse JSON — fail closed
  process.stderr.write('Blocked: YOLO hook failed to parse Edit/Write tool input as JSON.\n');
  process.exit(2);
}

const target = input?.tool_input?.file_path || input?.tool_input?.notebook_path || '';
const tool = input?.tool_name || 'unknown';

if (!target) process.exit(0); // No target — nothing to gate

// Allow temp/dev paths
if (/^\/(tmp|dev|var\/tmp)\//.test(target)) process.exit(0);

const repo = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const slug = getActiveFeature(repo);
if (!slug) process.exit(0); // No active feature — allow

const featureFile = path.join(repo, '.planning', 'features', slug, 'feature.md');
const fs = require('fs');
if (!fs.existsSync(featureFile)) process.exit(0); // Graceful — no plan file

if (isPathInScope(featureFile, target, repo)) process.exit(0);

// Out of scope — block
process.stderr.write(`YOLO gate: '${target}' is not in the plan scope for feature '${slug}'.

To proceed, choose one:
  1. Add the path to a task's 'files:' annotation in ${featureFile}
  2. Split this change into a separate feature
  3. Set YOLO_BYPASS=1 for this shell session

Tool: ${tool}
`);

if (process.env.YOLO_BYPASS === '1') {
  process.stderr.write('YOLO gate: bypass honored (YOLO_BYPASS=1)\n');
  auditLog(repo, 'bypass', 'pre-write', slug, target, tool);
  process.exit(0);
}

auditLog(repo, 'block', 'pre-write', slug, target, tool);
process.exit(2);
