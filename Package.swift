// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RagnarNetworking",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "RagnarNetworking",
            targets: ["RagnarNetworking"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "RagnarNetworking",
            dependencies: []
        ),
        .testTarget(
            name: "RagnarNetworkingTests",
            dependencies: ["RagnarNetworking"]
        )
    ]
)
