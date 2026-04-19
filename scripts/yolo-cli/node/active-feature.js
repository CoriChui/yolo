#!/usr/bin/env node
'use strict';

const { getActiveFeature, getCurrentPhase } = require('./yolo');

const args = process.argv.slice(2);
let repo = '.';
let format = 'plain';

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--repo' && args[i + 1]) { repo = args[++i]; continue; }
  if (args[i] === '--format' && args[i + 1]) { format = args[++i]; continue; }
}

if (format !== 'plain' && format !== 'status') {
  process.stderr.write(`Error: --format must be 'plain' or 'status', got '${format}'\n`);
  process.exit(1);
}

const slug = getActiveFeature(repo);
if (!slug) process.exit(1);

const phase = getCurrentPhase(repo) || 'plan';

if (format === 'status') {
  process.stdout.write(`yolo: ${slug} · ${phase}\n`);
} else {
  process.stdout.write(`${slug} ${phase}\n`);
}
