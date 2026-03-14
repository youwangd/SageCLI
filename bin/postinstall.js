#!/usr/bin/env node
// Post-install: check dependencies and make sage executable
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const sage = path.join(__dirname, '..', 'sage');

// Make sage executable
try {
  fs.chmodSync(sage, '755');
} catch (e) {}

// Check dependencies
const deps = ['bash', 'jq', 'tmux'];
const missing = deps.filter(d => {
  try { execSync(`which ${d}`, { stdio: 'ignore' }); return false; }
  catch { return true; }
});

if (missing.length > 0) {
  console.log(`\n⚡ sage installed! Missing optional dependencies: ${missing.join(', ')}`);
  console.log(`  Install with: ${process.platform === 'darwin' ? 'brew' : 'apt'} install ${missing.join(' ')}\n`);
} else {
  console.log('\n⚡ sage installed successfully! Run: sage init\n');
}
