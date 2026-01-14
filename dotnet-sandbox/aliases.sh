#!/usr/bin/env bash
# Placeholder: Will be implemented in fn-1.4
# Shell aliases for dotnet-sandbox (csd, csd-stop-all)
# Note: No strict mode - this file is sourced into interactive shells
# Only warn once in interactive shells to avoid noise
if [[ $- == *i* ]] && [[ -z "$_DOTNET_SANDBOX_ALIASES_WARNED" ]]; then
  echo "WARNING: aliases.sh not yet implemented (see fn-1.4)" >&2
  export _DOTNET_SANDBOX_ALIASES_WARNED=1
fi
# Return 0 when sourced, exit 1 when executed directly
return 0 2>/dev/null || exit 1
