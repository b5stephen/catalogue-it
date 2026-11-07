#!/bin/zsh
# Xcode Cloud runs this after every xcodebuild action. For an App Store–signed archive it writes
# TestFlight's "What to Test" notes from the latest commits; Xcode Cloud reads
# TestFlight/WhatToTest.<locale>.txt beside the project when it uploads the build.
set -eu

[[ -d "${CI_APP_STORE_SIGNED_APP_PATH:-}" ]] || exit 0

notes_dir="$CI_PRIMARY_REPOSITORY_PATH/TestFlight"
mkdir -p "$notes_dir"

# Xcode Cloud clones shallowly.
git -C "$CI_PRIMARY_REPOSITORY_PATH" fetch --deepen 10 --quiet || true
git -C "$CI_PRIMARY_REPOSITORY_PATH" log -10 --no-merges --pretty=format:'• %s' \
    | head -c 3900 > "$notes_dir/WhatToTest.en-US.txt"
