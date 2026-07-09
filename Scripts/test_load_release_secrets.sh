#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_HOME=$(mktemp -d "${TMPDIR:-/tmp}/codexbar-release-secrets.XXXXXX")
ASC_DIR="$TMP_HOME/.codex-secrets/apple/app-store-connect"
trap 'rm -rf "$TMP_HOME"' EXIT
mkdir -p "$ASC_DIR"

write_generic_env() {
  local path=$1 prefix=$2
  printf '%s\n' \
    "APP_STORE_CONNECT_KEY_ID=${prefix}_KEY" \
    "APP_STORE_CONNECT_ISSUER_ID=${prefix}_ISSUER" \
    "APP_STORE_CONNECT_API_KEY_FILE=/tmp/${prefix}-key.p8" \
    "APP_STORE_CONNECT_API_KEY_P8=${prefix}_P8" \
    > "$path"
}

write_alias_env() {
  local path=$1 prefix=$2
  printf '%s\n' \
    "APP_STORE_CONNECT_APP_MANAGER_KEY_ID=${prefix}_KEY" \
    "APP_STORE_CONNECT_APP_MANAGER_ISSUER_ID=${prefix}_ISSUER" \
    "APP_STORE_CONNECT_APP_MANAGER_API_KEY_FILE=/tmp/${prefix}-key.p8" \
    "APP_STORE_CONNECT_APP_MANAGER_API_KEY_P8=${prefix}_P8" \
    > "$path"
}

assert_credentials() {
  local expected=$1
  [[ "$APP_STORE_CONNECT_KEY_ID" == "${expected}_KEY" ]]
  [[ "$APP_STORE_CONNECT_ISSUER_ID" == "${expected}_ISSUER" ]]
  [[ "$APP_STORE_CONNECT_API_KEY_FILE" == "/tmp/${expected}-key.p8" ]]
  [[ "$APP_STORE_CONNECT_API_KEY_P8" == "${expected}_P8" ]]
  [[ "$APP_STORE_CONNECT_APP_MANAGER_KEY_ID" == "$APP_STORE_CONNECT_KEY_ID" ]]
  [[ "$APP_STORE_CONNECT_APP_MANAGER_ISSUER_ID" == "$APP_STORE_CONNECT_ISSUER_ID" ]]
  [[ "$APP_STORE_CONNECT_APP_MANAGER_API_KEY_FILE" == "$APP_STORE_CONNECT_API_KEY_FILE" ]]
  [[ "$APP_STORE_CONNECT_APP_MANAGER_API_KEY_P8" == "$APP_STORE_CONNECT_API_KEY_P8" ]]
}

run_case() {
  local expected=$1 release_env=${2:-}
  HOME="$TMP_HOME" CODEXBAR_RELEASE_ENV="$release_env" EXPECTED="$expected" ROOT="$ROOT" \
    ASSERT_FN="$(declare -f assert_credentials)" \
    bash -c '
      unset CODEXBAR_RELEASE_SECRETS_LOADED
      source "$ROOT/Scripts/load-release-secrets.sh"
      eval "$ASSERT_FN"
      assert_credentials "$EXPECTED"
    '
}

# The env-only global installation supports canonical generic names.
write_generic_env "$ASC_DIR/app-manager.env" GLOBAL_GENERIC
run_case GLOBAL_GENERIC

# App Manager-scoped aliases normalize into the canonical release variables.
write_alias_env "$ASC_DIR/app-manager.env" GLOBAL_ALIAS
run_case GLOBAL_ALIAS

# The helper is preferred over the direct global env and supports alias output.
write_alias_env "$ASC_DIR/load-app-manager-env.sh" GLOBAL_HELPER
run_case GLOBAL_HELPER

# An explicit CodexBar release env overrides every global default, and the
# scoped aliases are mirrored back from the winning canonical values.
write_generic_env "$TMP_HOME/project-release.env" PROJECT
run_case PROJECT "$TMP_HOME/project-release.env"

echo "release secret loader precedence and alias tests passed"
