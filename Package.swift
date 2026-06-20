// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgencyOS",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AgencyOS",
            path: "Sources/AgencyOS"
        )
    ]
)
