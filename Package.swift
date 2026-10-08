// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SegmentTimer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SegmentTimer",
            path: "Sources/SegmentTimer"
        )
    ]
)
