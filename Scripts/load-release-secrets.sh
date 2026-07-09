#!/usr/bin/env bash

if [[ -n "${CODEXBAR_RELEASE_SECRETS_LOADED:-}" ]]; then
  return 0
fi

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DEFAULT_RELEASE_ENV="$HOME/.codexbar-secrets/codexbar-release.env"
GLOBAL_APP_MANAGER_ASC_HELPER="$HOME/.codex-secrets/apple/app-store-connect/load-app-manager-env.sh"
RELEASE_ENV_CANDIDATES=()

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

if [[ -f "${GLOBAL_APP_MANAGER_ASC_HELPER}" ]]; then
  # shellcheck disable=SC1090
  source "${GLOBAL_APP_MANAGER_ASC_HELPER}"
fi

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
