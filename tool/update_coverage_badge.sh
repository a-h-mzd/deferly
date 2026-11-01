#!/bin/sh
# Publishes the coverage badge data to the `badges` branch, which the README
# badge reads through shields.io. Used by CI (.github/workflows/ci.yml).
#
# Usage: tool/update_coverage_badge.sh <percent>
# Needs GH_TOKEN and GITHUB_REPOSITORY (both set by GitHub Actions).
set -eu

percent="$1"
if [ "$percent" -ge 90 ]; then color=brightgreen
elif [ "$percent" -ge 75 ]; then color=yellow
else color=red; fi

dir=$(mktemp -d)
printf '{"schemaVersion":1,"label":"coverage","message":"%s%%","color":"%s"}\n' \
  "$percent" "$color" > "$dir/coverage.json"

cd "$dir"
git init -q -b badges
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add coverage.json
git commit -q -m "Update coverage badge to $percent%"
git push -q -f "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" badges
