#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/clang-cache dist
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" -D DESIGN_PREVIEW -parse-as-library \
    -module-cache-path "$PWD/.build/clang-cache" \
    Sources/ClipShelf/*.swift Tools/RenderPreview.swift -o .build/RenderPreview
.build/RenderPreview
