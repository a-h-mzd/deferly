#!/bin/sh
# Runs the format, analysis, test and coverage checks.
# Used by CI (.github/workflows/ci.yml); can also be run locally.
set -eu
cd "$(dirname "$0")/.."

# Minimum line and branch coverage of lib/, in percent.
MIN_COVERAGE="${MIN_COVERAGE:-100}"

echo '==> dart pub get'
dart pub get >/dev/null

echo '==> dart format'
dart format --output=none --set-exit-if-changed .

echo '==> dart analyze'
dart analyze --fatal-infos

echo '==> dart test'
dart test --coverage-path=coverage/lcov.info --branch-coverage

echo '==> coverage'
lines=$(awk -F: '/^LF:/ {t += $2} /^LH:/ {h += $2}
  END {printf "%d", t ? h * 100 / t : 100}' coverage/lcov.info)
branches=$(awk -F, '/^BRDA:/ {t++; if ($4 != "-" && $4 != "0") h++}
  END {printf "%d", t ? h * 100 / t : 100}' coverage/lcov.info)
echo "Lines: $lines%, branches: $branches% (minimum $MIN_COVERAGE%)"

# Lets CI use the result for the coverage badge.
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "percent=$lines" >> "$GITHUB_OUTPUT"
fi

if [ "$lines" -lt "$MIN_COVERAGE" ] || [ "$branches" -lt "$MIN_COVERAGE" ]; then
  echo "Coverage is below $MIN_COVERAGE%." >&2
  exit 1
fi
