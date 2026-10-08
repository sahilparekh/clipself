// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipShelf",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ClipShelf", targets: ["ClipShelf"])],
    targets: [
        .executableTarget(name: "ClipShelf"),
        .testTarget(name: "ClipShelfTests", dependencies: ["ClipShelf"])
    ]
)
