#!/usr/bin/env bash

set -euo pipefail

input="${1:-/dev/stdin}"

jq -e '
  (.check_runs | type == "array")
  and (.check_runs | length > 0)
  and all(.check_runs[]; .status == "completed" and .conclusion == "success")
' "$input" >/dev/null
