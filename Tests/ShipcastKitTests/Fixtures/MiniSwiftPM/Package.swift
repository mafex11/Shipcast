// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiniSwiftPM",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MiniSwiftPM", targets: ["MiniSwiftPM"]),
    ],
    targets: [
        .executableTarget(name: "MiniSwiftPM"),
    ]
)
