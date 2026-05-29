#!/bin/bash
# Build Crystal V2 LSP server

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building Crystal V2 LSP server..."

# Create bin directory if it doesn't exist
mkdir -p bin

# Compile LSP server (debug build, skip OpenSSL/LibreSSL)
crystal build -s -p -t src/lsp_main.cr -o bin/adamas_lsp -D without_openssl

echo "✓ LSP server built: bin/adamas_lsp"
echo ""
echo "To test:"
echo "  ./bin/adamas_lsp"
