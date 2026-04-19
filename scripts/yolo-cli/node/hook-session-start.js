#!/usr/bin/env node
'use strict';

const path = require('path');
const fs = require('fs');
const { getActiveFeature, getCurrentPhase } = require('./yolo');

const repo = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const slug = getActiveFeature(repo);
const phase = getCurrentPhase(repo) || 'plan';

let context;

if (slug) {
  const featureFile = path.join(repo, '.planning', 'features', slug, 'feature.md');
  if (fs.existsSync(featureFile)) {
    context = `YOLO active feature: ${slug} (phase: ${phase}). ` +
      `Feature plan at ${featureFile}. ` +
      `Scope enforcement is ON — edits outside the plan's declared files will be blocked. ` +
      `Drive the loop: think → plan → do → check → ship. ` +
      `Use scripts/yolo-cli/commit.sh for commits (adds YOLO-Feature/YOLO-Phase trailers). ` +
      `Use scripts/yolo-cli/reconcile.sh to check progress against git evidence.`;
  } else {
    context = `YOLO: on feature branch '${slug}' but no plan file at ${featureFile}. ` +
      `Create the plan file to enable scope enforcement, or switch to main.`;
  }
} else {
  // Check for existing features
  const featDir = path.join(repo, '.planning', 'features');
  let features = [];
  try {
    const dirs = fs.readdirSync(featDir, { withFileTypes: true });
    features = dirs
      .filter(d => d.isDirectory() && d.name !== 'done')
      .filter(d => fs.existsSync(path.join(featDir, d.name, 'feature.md')))
      .map(d => d.name);
  } catch {}

  if (features.length > 0) {
    context = `YOLO: not on a feature branch. Existing features: ${features.join(', ')}. ` +
      `Switch to a feature branch to resume, or describe new work to start.`;
  } else {
    context = `YOLO framework available. To start a feature: describe what you want to build. ` +
      `I'll create a feature branch, write a plan at .planning/features/<slug>/feature.md, ` +
      `and drive the loop (think → plan → do → check → ship) with scope enforcement.`;
  }
}

const escaped = context.replace(/"/g, '\\"').replace(/\n/g, ' ');
process.stdout.write(JSON.stringify({
  hookSpecificOutput: {
    hookEventName: 'SessionStart',
    additionalContext: context,
  }
}));
