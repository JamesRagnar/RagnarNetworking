// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RagnarNetworking",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
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
