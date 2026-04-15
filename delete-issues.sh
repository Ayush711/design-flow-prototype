#!/bin/bash
set -euo pipefail

# Resolve gh
if ! command -v gh &>/dev/null; then
  if [ -f "/c/Program Files/GitHub CLI/gh.exe" ]; then
    gh() { "/c/Program Files/GitHub CLI/gh.exe" "$@"; }
  elif [ -f "/mnt/c/Program Files/GitHub CLI/gh.exe" ]; then
    gh() { "/mnt/c/Program Files/GitHub CLI/gh.exe" "$@"; }
  fi
fi

REPO="AIS-Commercial-Business-Unit/Helix"

for num in $(seq 1 19); do
  node_id=$(gh api "repos/$REPO/issues/$num" --jq '.node_id' 2>/dev/null || true)
  if [ -z "$node_id" ] || [ "$node_id" = "null" ]; then
    echo "⏭️  Skipped #$num (not found)"
    continue
  fi
  result=$(gh api graphql \
    -f query='mutation($id: ID!) { deleteIssue(input: { issueId: $id }) { clientMutationId } }' \
    -f id="$node_id" 2>&1) \
    && echo "🗑️  Deleted #$num" \
    || echo "⚠️  Failed #$num: $result"
done

echo "✅ Done."
