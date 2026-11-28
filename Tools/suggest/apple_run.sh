#!/bin/bash
# Apple's suggestion bar for a cases file, on a simulator with the English (US) keyboard only:
#   Tools/suggest/apple_run.sh <sim udid> <cases.json> <out.jsonl>
# Prints nothing to the keyboard's learning: the app sets the text, only the case's letters are typed.
set -euo pipefail
cases="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
out="$(cd "$(dirname "$3")" && pwd)/$(basename "$3")"
log="${out%.jsonl}.log"
cd "$(dirname "$0")/AppleRef"
xcodegen generate -q
TEST_RUNNER_CASES="$cases" xcodebuild test -project AppleRef.xcodeproj -scheme AppleRef \
  -destination "id=$1" -derivedDataPath "${TMPDIR:-/tmp}/appleref-dd" -only-testing:AppleRefUITests/AppleRefUITests/testSuggestionBar \
  CODE_SIGNING_ALLOWED=NO > "$log" 2>&1 || { tail -20 "$log"; echo "the run failed: nothing written (log: $log)"; exit 1; }
grep '^SUGGEST' "$log" | cut -f2- > "$out"
echo "$(wc -l < "$out") cases read → $out"
