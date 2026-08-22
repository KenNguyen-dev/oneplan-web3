#!/usr/bin/env bash
# Flip the active server env between local dev and prod profiles.
# Usage: ./scripts/use-env.sh dev|prod
set -euo pipefail
cd "$(dirname "$0")/.."
target="${1:-}"
case "$target" in dev|prod) ;; *) echo "usage: $0 dev|prod"; exit 1;; esac
ln -sf ".env.$target.local" .env
echo "active server env -> .env.$target.local  ($(ls -l .env | sed 's/.*-> //'))"
