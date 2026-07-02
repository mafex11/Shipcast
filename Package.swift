// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shipcast",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "shipcast", targets: ["ShipcastCLI"]),
        .library(name: "ShipcastKit", targets: ["ShipcastKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/dduan/TOMLDecoder", from: "0.2.2"),
    ],
    targets: [
        .executableTarget(
            name: "ShipcastCLI",
            dependencies: [
                "ShipcastKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "ShipcastKit",
            dependencies: [
                .product(name: "TOMLDecoder", package: "TOMLDecoder"),
            ]
        ),
        .testTarget(
            name: "ShipcastKitTests",
            dependencies: ["ShipcastKit"]
        ),
    ]
)
