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
        .package(url: "https://github.com/christophhagen/ClairvoyantClient", from: "0.4.3"),
        .package(url: "https://github.com/christophhagen/Clairvoyant", from: "0.14.2"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "ClairvoyantVapor",
            dependencies: [
                .product(name: "Clairvoyant", package: "Clairvoyant"),
                .product(name: "ClairvoyantClient", package: "ClairvoyantClient"),
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
