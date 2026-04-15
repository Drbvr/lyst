#!/usr/bin/env bash
# verify-project-files.sh
#
# Checks that every .swift file under the ListApp/ app target directories
# is registered in ListApp.xcodeproj/project.pbxproj.
#
# Usage: ./scripts/verify-project-files.sh
# Exit code: 0 = OK, 1 = missing files found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_FILE="$REPO_ROOT/ListApp.xcodeproj/project.pbxproj"

# Directories whose Swift files must all be registered in project.pbxproj.
# Sources/Core is a native Xcode framework target (not SPM auto-discovery),
# so new files there also require explicit registration.
APP_DIRS=(
  "$REPO_ROOT/ListApp"
  "$REPO_ROOT/Sources/Core"
)

MISSING=()

for dir in "${APP_DIRS[@]}"; do
  while IFS= read -r -d '' swift_file; do
    filename="$(basename "$swift_file")"
    if ! grep -qF "$filename" "$PROJECT_FILE"; then
      MISSING+=("$swift_file")
    fi
  done < <(find "$dir" -name "*.swift" -print0)
done

if [ ${#MISSING[@]} -eq 0 ]; then
  echo "✓ All Swift files are registered in project.pbxproj"
  exit 0
else
  echo "✗ The following Swift files are NOT registered in project.pbxproj:"
  for f in "${MISSING[@]}"; do
    echo "  - ${f#$REPO_ROOT/}"
  done
  echo ""
  echo "Add them to the Xcode project (drag into Xcode, or edit project.pbxproj manually)."
  exit 1
fi
