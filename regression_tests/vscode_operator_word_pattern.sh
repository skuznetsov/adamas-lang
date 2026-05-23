#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

node - "$repo_root/vscode-extension/language-configuration.json" <<'NODE'
const fs = require('fs');
const configPath = process.argv[2];
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
const pattern = config.wordPattern;

if (typeof pattern !== 'string' || pattern.length === 0) {
  throw new Error('language-configuration.json must define wordPattern');
}

const re = new RegExp(pattern, 'g');
function words(text) {
  re.lastIndex = 0;
  return Array.from(text.matchAll(re), (match) => match[0]);
}

const line = 'self < 0 ? 0_u8 &- self : to_u8!; cmp = self <=> other';
const got = words(line);
for (const token of ['self', '<', '0_u8', '&-', 'to_u8!', '<=>', 'other']) {
  if (!got.includes(token)) {
    throw new Error(`missing token ${token}; got ${JSON.stringify(got)}`);
  }
}

if (got.includes('&') || got.includes('-')) {
  throw new Error(`&- must be one word token; got ${JSON.stringify(got)}`);
}
NODE
