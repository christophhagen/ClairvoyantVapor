// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "ClairvoyantVapor",
    platforms: [.macOS(.v12), .iOS(.v14), .watchOS(.v9)],
    products: [
        .library(
            name: "ClairvoyantVapor",
            targets: ["ClairvoyantVapor"]),
    ],
    dependencies: [
        .package(url: "https://github.com/christophhagen/Clairvoyant", from: "0.8.0"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "ClairvoyantVapor",
            dependencies: [
                .product(name: "Clairvoyant", package: "Clairvoyant"),
                .product(name: "Vapor", package: "vapor"),
            ]),
        .testTarget(
            name: "ClairvoyantVaporTests",
            dependencies: [
                .product(name: "XCTVapor", package: "vapor"),
                "ClairvoyantVapor",
            ]),
    ]
)
