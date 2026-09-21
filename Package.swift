// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Stickr",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "StickrCore"),
        .executableTarget(name: "stickr", dependencies: ["StickrCore"]),
        .testTarget(name: "StickrCoreTests", dependencies: ["StickrCore"]),
    ]
)
