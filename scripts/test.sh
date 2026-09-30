#!/bin/zsh
# Runs the core tests. With only the Command Line Tools, SwiftPM sometimes forgets to load the
# swift-testing macro plugin, so it's passed explicitly; a separate build folder keeps release builds out of the way.
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --scratch-path .build-test \
    -Xswiftc -load-plugin-library \
    -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib "$@"
