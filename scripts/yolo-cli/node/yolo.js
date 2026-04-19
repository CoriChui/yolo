'use strict';

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

function git(args, cwd = '.') {
  try {
    return execSync(`git ${args}`, { cwd, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim();
  } catch { return ''; }
}

function getActiveFeature(repo = '.') {
  const branch = git('symbolic-ref --short HEAD', repo);
  const m = branch.match(/^feature\/(.+)$/);
  return m ? m[1] : null;
}

function parseTrailer(repo, ref, name) {
  const msg = git(`log -1 --format=%B ${ref}`, repo);
  if (!msg) return null;
  try {
    const trailers = execSync('git interpret-trailers --parse', {
      input: msg, cwd: repo, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe']
    }).trim();
    const re = new RegExp(`^${name}:\\s*(.+)$`, 'im');
    const m = trailers.match(re);
    return m ? m[1].trim() : null;
  } catch { return null; }
}

const _phaseCache = new Map();

function getCurrentPhase(repo = '.', branch = 'HEAD') {
  const slug = getActiveFeature(repo) || 'nofeat';
  const sha = git('rev-parse --short=12 HEAD', repo);
  const key = `${sha}-${slug}-${branch}`;
  if (_phaseCache.has(key)) return _phaseCache.get(key);

  const shas = git(`log -n 50 --format=%H --grep=^YOLO-Phase: ${branch}`, repo);
  for (const commit of shas.split('\n').filter(Boolean)) {
    const phase = parseTrailer(repo, commit, 'YOLO-Phase');
    if (!phase) continue;
    if (slug !== 'nofeat') {
      const feat = parseTrailer(repo, commit, 'YOLO-Feature');
      if (feat !== slug) continue;
    }
    _phaseCache.set(key, phase);
    return phase;
  }
  _phaseCache.set(key, '');
  return '';
}

function normalizePath(p, repoRoot) {
  const abs = path.resolve(repoRoot, p);
  try {
    if (fs.existsSync(abs)) return fs.realpathSync(abs);
    const dir = path.dirname(abs);
    if (fs.existsSync(dir)) return path.join(fs.realpathSync(dir), path.basename(abs));
  } catch {}
  return abs;
}

function getRepoRoot(featureFile) {
  if (featureFile) {
    const dir = path.dirname(featureFile);
    const root = git('rev-parse --show-toplevel', dir);
    if (root) try { return fs.realpathSync(root); } catch {}
  }
  const root = git('rev-parse --show-toplevel');
  if (root) try { return fs.realpathSync(root); } catch {}
  return fs.realpathSync(process.cwd());
}

function isPathInScope(featureFile, target, repoRoot) {
  if (!target) return false;
  if (!repoRoot) repoRoot = getRepoRoot(featureFile);
  try { repoRoot = fs.realpathSync(repoRoot); } catch { return false; }

  const absTarget = normalizePath(target, repoRoot);
  if (!absTarget.startsWith(repoRoot + path.sep) && absTarget !== repoRoot) return false;

  const rel = path.relative(repoRoot, absTarget);
  if (rel === '.planning' || rel.startsWith('.planning' + path.sep)) return true;
  if (!featureFile || !fs.existsSync(featureFile)) return false;

  const content = fs.readFileSync(featureFile, 'utf8');
  let inPlan = false;

  for (const line of content.split('\n')) {
    if (/^##\s+Plan/.test(line)) { inPlan = true; continue; }
    if (inPlan && /^##\s/.test(line)) break;
    if (!inPlan || !line.includes('files:')) continue;

    for (let entry of line.split('files:')[1].split(',')) {
      entry = entry.trim();
      if ((entry.startsWith('"') && entry.endsWith('"')) ||
          (entry.startsWith("'") && entry.endsWith("'"))) entry = entry.slice(1, -1);
      entry = entry.replace(/\.$/, '');
      if (!entry) continue;

      const absEntry = normalizePath(entry, repoRoot);
      if (!absEntry.startsWith(repoRoot + path.sep) && absEntry !== repoRoot) continue;
      const entryRel = path.relative(repoRoot, absEntry);
      if (rel === entryRel || rel.startsWith(entryRel + path.sep)) return true;
    }
  }
  return false;
}

function auditLog(repo, event, hook, feature, target, extra = '') {
  try {
    const dir = path.join(repo, '.planning');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, '.audit.log');
    const ts = new Date().toISOString();
    const c = s => String(s).replace(/[\t\n\r]/g, ' ');
    fs.appendFileSync(file, [ts, event, hook, c(feature), c(target), c(extra)].join('\t') + '\n', { mode: 0o600 });
  } catch {}
}

function readStdin() {
  try { return fs.readFileSync(0, 'utf8'); } catch { return ''; }
}

function parseStdin() {
  const raw = readStdin();
  if (!raw) return null;
  try { return JSON.parse(raw); } catch { return null; }
}

module.exports = {
  git, getActiveFeature, parseTrailer, getCurrentPhase,
  normalizePath, getRepoRoot, isPathInScope,
  auditLog, readStdin, parseStdin,
};
