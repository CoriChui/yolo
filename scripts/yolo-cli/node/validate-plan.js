#!/usr/bin/env node
'use strict';

const fs = require('fs');

const args = process.argv.slice(2);
let featureFile = '', noTestSuite = false;
for (const a of args) {
  if (a === '--no-test-suite') { noTestSuite = true; continue; }
  if (a.startsWith('-')) { process.stderr.write(`Unknown option: ${a}\n`); process.exit(1); }
  if (!featureFile) featureFile = a;
  else { process.stderr.write(`Unexpected argument: ${a}\n`); process.exit(1); }
}

if (!featureFile) { process.stderr.write('Usage: validate-plan.js <feature-file> [--no-test-suite]\n'); process.exit(1); }
if (!fs.existsSync(featureFile)) { process.stderr.write(`Error: file not found: ${featureFile}\n`); process.exit(1); }

const content = fs.readFileSync(featureFile, 'utf8');
const tasks = [];
let inPlan = false, currentTask = null;

for (const line of content.split('\n')) {
  if (/^##\s+Plan/.test(line)) { inPlan = true; continue; }
  if (inPlan && /^##\s/.test(line)) break;
  if (!inPlan) continue;

  const taskMatch = line.match(/^(\d+)\.\s+\[([ xX])\]\s+(.*)/);
  if (taskMatch) {
    currentTask = { num: taskMatch[1], desc: taskMatch[3], testAnn: '', filesLine: '' };
    if (/(?:^|[\s(])test:\s*none/i.test(currentTask.desc)) currentTask.testAnn = 'none';
    else if (/test:/i.test(currentTask.desc)) {
      const v = currentTask.desc.replace(/.*test:\s*/i, '');
      currentTask.testAnn = v ? 'yes' : 'empty';
    }
    if (/files:/.test(currentTask.desc)) currentTask.filesLine = currentTask.desc;
    tasks.push(currentTask);
    continue;
  }

  const subMatch = line.match(/^\s+-\s+(.*)/);
  if (subMatch && currentTask) {
    const sub = subMatch[1];
    if (/^test:\s*none/i.test(sub)) currentTask.testAnn = 'none';
    else if (/^test:/i.test(sub)) {
      const v = sub.replace(/^test:\s*/i, '');
      currentTask.testAnn = v ? 'yes' : 'empty';
    }
    if (/^files:/i.test(sub)) currentTask.filesLine = sub;
  }
}

const errors = [], warnings = [];

if (!inPlan) errors.push('No ## Plan section found — must have a Plan section with at least 2 tasks');
else if (tasks.length === 0) errors.push('Plan section exists but contains no tasks — must have at least 2 tasks');

if (tasks.length === 1) errors.push('Only 1 task — minimum is 2');
else if (tasks.length > 12) errors.push(`Too many tasks (${tasks.length}) — maximum is 12, split feature into smaller pieces`);

let testNoneCount = 0;
for (const t of tasks) {
  if (t.testAnn === 'none') testNoneCount++;
  if (t.testAnn === 'empty') errors.push(`Task ${t.num}: empty test: annotation — specify a test command or 'test: none (justification)'`);
  if (!t.testAnn) warnings.push(`Task ${t.num}: missing test: annotation`);

  const clean = t.desc.replace(/\([^)]*test:[^)]*\)/g, '').replace(/\([^)]*files:[^)]*\)/g, '');
  if (clean.split(/\s+/).filter(Boolean).length < 20)
    warnings.push(`Task ${t.num}: description too short (recommended 20+ words)`);
}

if (tasks.length > 0 && !noTestSuite && testNoneCount * 2 > tasks.length)
  errors.push(`Too many tasks with test:none (${testNoneCount} of ${tasks.length}) — TDD requires most tasks to have tests (use --no-test-suite to skip)`);

if (warnings.length > 0) {
  process.stderr.write(`Plan validation warnings (${warnings.length}):\n`);
  for (const w of warnings) process.stderr.write(`  - ${w}\n`);
}

if (errors.length > 0) {
  process.stderr.write(`Plan validation FAILED (${errors.length} error(s)):\n`);
  for (const e of errors) process.stderr.write(`  - ${e}\n`);
  process.exit(1);
}

process.stdout.write(`Plan validation passed: ${tasks.length} task(s), ${testNoneCount} with test:none\n`);
