// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Transcoding",
    platforms: [.iOS(.v15), .macOS(.v13), .visionOS(.v1), .tvOS(.v15)],
    products: [.library(name: "Transcoding", targets: ["Transcoding"])],
    dependencies: [
      .package(url: "https://github.com/apple/swift-log.git", from: "1.5.4")
    ],
    targets: [
        .target(name: "Transcoding", dependencies: [
            .product(name: "Logging", package: "swift-log")
        ]),
        .testTarget(name: "TranscodingTests", dependencies: [
            "Transcoding",
            .product(name: "Logging", package: "swift-log")
        ], resources: [.process("Resources")])
    ]
)
