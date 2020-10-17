// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "CombineProperty",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(
            name: "CombineProperty",
            targets: ["CombineProperty"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CombineProperty",
            dependencies: []),
        .testTarget(
            name: "CombinePropertyTests",
            dependencies: ["CombineProperty"]),
    ]
)
