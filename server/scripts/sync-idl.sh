#!/usr/bin/env bash
# Refreshes the committed IDL and its TypeScript type from the Anchor build.
# Run after any change to the program, then commit the result.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/solana/target"
DEST="$ROOT/server/src/solana"

if [ ! -f "$SRC/idl/oneplan_vault.json" ]; then
  echo "No built IDL. Run 'anchor build' in solana/ first." >&2
  exit 1
fi

cp "$SRC/idl/oneplan_vault.json" "$DEST/idl/oneplan_vault.json"
cp "$SRC/types/oneplan_vault.ts" "$DEST/types/oneplan_vault.ts"
echo "IDL and types synced to server/src/solana/"
