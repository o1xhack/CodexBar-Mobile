#!/usr/bin/env bash

if [[ -n "${CODEXBAR_RELEASE_SECRETS_LOADED:-}" ]]; then
  return 0
fi

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DEFAULT_RELEASE_ENV="$HOME/.codexbar-secrets/codexbar-release.env"
GLOBAL_APP_MANAGER_ASC_DIR="$HOME/.codex-secrets/apple/app-store-connect"
GLOBAL_APP_MANAGER_ASC_HELPER="$GLOBAL_APP_MANAGER_ASC_DIR/load-app-manager-env.sh"
GLOBAL_APP_MANAGER_ASC_ENV="$GLOBAL_APP_MANAGER_ASC_DIR/app-manager.env"
RELEASE_ENV_CANDIDATES=()

if [[ -f "${GLOBAL_APP_MANAGER_ASC_HELPER}" ]]; then
  # shellcheck disable=SC1090
  source "${GLOBAL_APP_MANAGER_ASC_HELPER}"
elif [[ -f "${GLOBAL_APP_MANAGER_ASC_ENV}" ]]; then
  # Support the documented env-only setup when the optional loader helper
  # has not been installed on this Mac.
  # shellcheck disable=SC1090
  source "${GLOBAL_APP_MANAGER_ASC_ENV}"
fi

if [[ -n "${CODEXBAR_RELEASE_ENV:-}" ]]; then
  RELEASE_ENV_CANDIDATES+=("${CODEXBAR_RELEASE_ENV}")
fi
RELEASE_ENV_CANDIDATES+=(
  "${DEFAULT_RELEASE_ENV}"
  "${ROOT}/.codexbar-release.local.env"
)

for release_env in "${RELEASE_ENV_CANDIDATES[@]}"; do
  if [[ -n "$release_env" && -f "$release_env" ]]; then
    # shellcheck disable=SC1090
    source "$release_env"
    break
  fi
done

if [[ -z "${SPARKLE_PRIVATE_KEY_FILE:-}" && -f "$HOME/.codexbar-secrets/sparkle_ed25519.key" ]]; then
  SPARKLE_PRIVATE_KEY_FILE="$HOME/.codexbar-secrets/sparkle_ed25519.key"
fi

if [[ -z "${APP_STORE_CONNECT_API_KEY_FILE:-}" && -n "${APP_STORE_CONNECT_KEY_ID:-}" ]]; then
  candidate_key="$HOME/.codexbar-secrets/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
  if [[ -f "$candidate_key" ]]; then
    APP_STORE_CONNECT_API_KEY_FILE="$candidate_key"
  fi
fi

export SPARKLE_PRIVATE_KEY_FILE
export APP_STORE_CONNECT_API_KEY_FILE
export APP_STORE_CONNECT_API_KEY_P8
export APP_STORE_CONNECT_KEY_ID
export APP_STORE_CONNECT_ISSUER_ID
export APP_STORE_CONNECT_APP_MANAGER_API_KEY_FILE
export APP_STORE_CONNECT_APP_MANAGER_KEY_ID
export CODEXBAR_RELEASE_SECRETS_LOADED=1
