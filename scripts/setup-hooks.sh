#!/usr/bin/env bash
# setup-hooks.sh
# Configures git to use the repo's shared .githooks directory.
# Run once after cloning: bash scripts/setup-hooks.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

git -C "$REPO_ROOT" config core.hooksPath .githooks
chmod +x "$REPO_ROOT/.githooks/"*

echo "✓ Git hooks configured (core.hooksPath = .githooks)"
echo "  Active hooks:"
for f in "$REPO_ROOT/.githooks/"*; do
  echo "    $(basename "$f")"
done
