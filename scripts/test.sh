#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/tests .build/clang-cache
cat > .build/tests/main.swift <<'SWIFT'
let tests = ClipHistoryTests()
tests.testRecopyMovesClipToFrontWithoutLosingPinOrIdentity()
tests.testRetentionKeepsPinsAndLatest200Clips()
tests.testExportPreservesExactTextAndChronologicalOrder()
try tests.testEmptyClipsAreIgnoredAndHistoryRoundTrips()
try tests.testOldTextHistoryStillLoads()
tests.testCycleWrapsInBothDirectionsAndResets()
try tests.testBinaryAndFileClipsRemainDistinctAndRoundTrip()
try tests.testExportMixedItemsWithoutOverwritingExistingFiles()
print("Passed 8 tests: history, migration, cycling, binary persistence, and mixed export.")
if try tests.checkClipboardTypesAndMissingFileProtection() {
    print("Passed file/image/PDF pasteboard round trips and missing-file protection.")
} else {
    print("SKIPPED pasteboard checks: macOS pasteboard service is unavailable in this environment.")
}
SWIFT
swiftc -swift-version 5 -module-cache-path "$PWD/.build/clang-cache" \
    Sources/ClipShelf/Clip.swift Sources/ClipShelf/ClipboardCodec.swift Sources/ClipShelf/ClipExporter.swift \
    Tests/ClipShelfTests/ClipHistoryTests.swift \
    .build/tests/main.swift -o .build/tests/HistoryTests
.build/tests/HistoryTests
