#!/usr/bin/env bash
set -euo pipefail

VERSION=${1:-}
CHANGELOG_FILE=${2:-}
RELEASE_BRANCH=${CODEXBAR_RELEASE_BRANCH:-mobile-dev}

if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version> [changelog_file]" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ -z "$CHANGELOG_FILE" ]]; then
  if [[ -f "$SCRIPT_DIR/../CHANGELOG.md" ]]; then
    CHANGELOG_FILE="$SCRIPT_DIR/../CHANGELOG.md"
  elif [[ -f "CHANGELOG.md" ]]; then
    CHANGELOG_FILE="CHANGELOG.md"
  elif [[ -f "../CHANGELOG.md" ]]; then
    CHANGELOG_FILE="../CHANGELOG.md"
  else
    echo "Error: Could not find CHANGELOG.md" >&2
    exit 1
  fi
fi

if [[ ! -f "$CHANGELOG_FILE" ]]; then
  echo "Error: Changelog file '$CHANGELOG_FILE' not found" >&2
  exit 1
fi

extract_version_section() {
  local version=$1
  local file=$2
  # Grab ONLY the first occurrence of `## <version>` — if the changelog ever
  # ends up with a duplicate heading for the same version (e.g. accidental
  # split across dates), the second occurrence must NOT be appended to the
  # first. We reach `exit` on any `## ` heading encountered after the first
  # match, regardless of whether it also matches `version`.
  awk -v version="$version" '
    BEGIN { found=0 }
    /^## / {
      if (found) { exit }
      if ($0 ~ "^##[[:space:]]+" version "([[:space:]].*|$)") { found=1; next }
    }
    found { print }
  ' "$file"
}

markdown_to_html() {
  local text=$1
  text=$(echo "$text" | sed 's/^### \(.*\)$/<h3>\1<\/h3>/')
  text=$(echo "$text" | sed 's/^## \(.*\)$/<h2>\1<\/h2>/')
  text=$(echo "$text" | sed 's/^- \*\*\([^*]*\)\*\*\(.*\)$/<li><strong>\1<\/strong>\2<\/li>/')
  text=$(echo "$text" | sed 's/^- \([^*].*\)$/<li>\1<\/li>/')
  text=$(echo "$text" | sed 's/\*\*\([^*]*\)\*\*/<strong>\1<\/strong>/g')
  text=$(echo "$text" | sed 's/`\([^`]*\)`/<code>\1<\/code>/g')
  text=$(echo "$text" | sed 's/\[\([^]]*\)\](\([^)]*\))/<a href="\2">\1<\/a>/g')
  echo "$text"
}

version_content=$(extract_version_section "$VERSION" "$CHANGELOG_FILE")
if [[ -z "$version_content" ]]; then
  echo "<h2>CodexBar $VERSION</h2>"
  echo "<p>Latest CodexBar update.</p>"
  echo "<p><a href=\"https://github.com/o1xhack/CodexBar-Mobile/blob/${RELEASE_BRANCH}/CHANGELOG.md\">View full changelog</a></p>"
  exit 0
fi

MOBILE_VERSION=""
if [[ -f "$SCRIPT_DIR/../version.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/../version.env"
fi
if [[ -n "$MOBILE_VERSION" ]]; then
  echo "<h2>CodexBar ${VERSION}-Mobile ${MOBILE_VERSION}</h2>"
else
  echo "<h2>CodexBar $VERSION</h2>"
fi

in_list=false
while IFS= read -r line; do
  # Markdown horizontal rule (---) — close any open list and emit <hr/>.
  # Must be checked BEFORE the "starts with -" branch, otherwise the line
  # would be wrapped in <ul> and rendered as literal text.
  if [[ "$line" =~ ^---+$ ]]; then
    if [[ "$in_list" == true ]]; then
      echo "</ul>"
      in_list=false
    fi
    echo "<hr/>"
    continue
  fi

  # List item: dash followed by a space (avoids matching "---" or "--foo").
  if [[ "$line" =~ ^-[[:space:]] ]]; then
    if [[ "$in_list" == false ]]; then
      echo "<ul>"
      in_list=true
    fi
    markdown_to_html "$line"
  else
    if [[ "$in_list" == true ]]; then
      echo "</ul>"
      in_list=false
    fi
    if [[ -n "$line" ]]; then
      markdown_to_html "$line"
    fi
  fi
done <<< "$version_content"

if [[ "$in_list" == true ]]; then
  echo "</ul>"
fi

echo "<p><a href=\"https://github.com/o1xhack/CodexBar-Mobile/blob/${RELEASE_BRANCH}/CHANGELOG.md\">View full changelog</a></p>"
