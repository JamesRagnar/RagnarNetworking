// swift-tools-version: 6.0
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
        ),
        .library(
            name: "RagnarWebSocket",
            targets: ["RagnarWebSocket"]
        ),
        .library(
            name: "RagnarSocketIO",
            targets: ["RagnarSocketIO"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "RagnarNetworking",
            dependencies: []
        ),
        .target(
            name: "RagnarWebSocket",
            dependencies: []
        ),
        .target(
            name: "RagnarSocketIO",
            dependencies: ["RagnarWebSocket"]
        ),
        .testTarget(
            name: "RagnarNetworkingTests",
            dependencies: ["RagnarNetworking"]
        ),
        .testTarget(
            name: "RagnarWebSocketTests",
            dependencies: ["RagnarWebSocket"]
        ),
        .testTarget(
            name: "RagnarSocketIOTests",
            dependencies: ["RagnarSocketIO", "RagnarWebSocket"]
        )
    ]
)
