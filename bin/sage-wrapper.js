#!/usr/bin/env node
// Thin wrapper that execs the bash sage script
const { execFileSync } = require('child_process');
const path = require('path');

const sage = path.join(__dirname, '..', 'sage');
const args = process.argv.slice(2);

try {
  execFileSync(sage, args, { stdio: 'inherit' });
} catch (err) {
  process.exit(err.status || 1);
}
