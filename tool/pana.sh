#!/bin/sh
# Fails if the package would lose any pub.dev points.
# Used by CI (.github/workflows/ci.yml); can also be run locally.
set -eu
cd "$(dirname "$0")/.."

if ! dart pub global list 2>/dev/null | grep -q '^pana '; then
  dart pub global activate pana >/dev/null
fi
echo '==> pana (pub.dev score)'
dart pub global run pana --no-warning --exit-code-threshold 0 .
