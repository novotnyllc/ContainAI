#!/usr/bin/env bash
# Verify that ghcr.io packages exist for retention policy checks.
# Note: There is no REST API to change package visibility. Container packages
# in ghcr.io inherit visibility from the repository by default (public repo = public packages).
# If packages need to be made public manually, use the GitHub UI or GraphQL API.
# See: https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${OWNER:?OWNER is required}"

packages=(
  containai-base
  containai
  containai-copilot
  containai-codex
  containai-claude
  containai-proxy
  containai-log-forwarder
  containai-payload
  containai-installer
  containai-metadata
)

echo "Checking package existence for retention policy..."
for pkg in "${packages[@]}"; do
  # Check if package exists (for org or user context)
  if gh api "/orgs/${OWNER}/packages/container/${pkg}" &>/dev/null; then
    echo "✓ $pkg exists (org)"
  elif gh api "/user/packages/container/${pkg}" &>/dev/null; then
    echo "✓ $pkg exists (user)"
  else
    echo "⚠ $pkg not found (may be first publish or private)"
  fi
done
