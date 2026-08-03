#!/usr/bin/env bash
# Deploys the complete fork CloudKit schema (Scripts/cloudkit/schema.ckdb),
# preserving the existing Mac-to-iPhone record types while adding fleet sync.
#
# Requires a CloudKit management token (create one at
# https://icloud.developer.apple.com/dashboard → account menu → Tokens,
# or via `xcrun cktool save-token`). Pass it via CLOUDKIT_MANAGEMENT_TOKEN
# or save it first with `xcrun cktool save-token`.
#
# Usage: Scripts/cloudkit/deploy_schema.sh development
# Production promotion must be performed in CloudKit Console after separate
# authorization; cktool's validate-schema endpoint is development-only.
set -euo pipefail

ENVIRONMENT="${1:-development}"
case "$ENVIRONMENT" in
  development|production) ;;
  *) echo "ERROR: environment must be development or production" >&2; exit 1 ;;
esac

if [[ "$ENVIRONMENT" == "production" ]]; then
  cat >&2 <<'EOF'
ERROR: Production schema promotion is intentionally not automated here.
Use CloudKit Console -> Schema -> Deploy Changes to Production after explicit
authorization, then run a read-only cktool export-schema Production readback.
EOF
  exit 2
fi

# CodexBar Mobile fork CloudKit identity. Never point this script at upstream's
# container: the fleet zone coexists with the existing Mac-to-iPhone schema.
TEAM_ID="3TUERHN53E"
CONTAINER_ID="iCloud.com.o1xhack.codexbar"
SCHEMA_FILE="$(cd "$(dirname "$0")" && pwd)/schema.ckdb"

TOKEN_ARGS=()
if [[ -n "${CLOUDKIT_MANAGEMENT_TOKEN:-}" ]]; then
  TOKEN_ARGS=(--token "$CLOUDKIT_MANAGEMENT_TOKEN")
fi

echo "Validating schema against $ENVIRONMENT..."
xcrun cktool validate-schema ${TOKEN_ARGS[@]+"${TOKEN_ARGS[@]}"} \
  --team-id "$TEAM_ID" --container-id "$CONTAINER_ID" \
  --environment "$ENVIRONMENT" --file "$SCHEMA_FILE"

echo "Importing schema into $ENVIRONMENT..."
xcrun cktool import-schema ${TOKEN_ARGS[@]+"${TOKEN_ARGS[@]}"} \
  --team-id "$TEAM_ID" --container-id "$CONTAINER_ID" \
  --environment "$ENVIRONMENT" --file "$SCHEMA_FILE"

echo "Done. Current $ENVIRONMENT schema:"
xcrun cktool export-schema ${TOKEN_ARGS[@]+"${TOKEN_ARGS[@]}"} \
  --team-id "$TEAM_ID" --container-id "$CONTAINER_ID" \
  --environment "$ENVIRONMENT"
