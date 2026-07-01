#!/usr/bin/env bash
# G3 contract guard: generic template and instance identity is keyed by
# semantic fields, not by display/rendered names.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

crystal spec --no-color spec/semantic/generic_identity_key_spec.cr

echo "PASS: generic semantic identity key contract"
