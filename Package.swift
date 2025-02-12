// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StoreManager",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "StoreManager",
            targets: ["StoreManager"]),
    ],
    dependencies: [
        .package(url: "https://github.com/evgenyneu/keychain-swift", from: "21.0.0"),
        .package(url: "https://github.com/rwbutler/connectivity", from: "6.1.1"),
    ],
    targets: [
        .target(
            name: "StoreManager",
            dependencies: [
                .product(name: "KeychainSwift", package: "keychain-swift"),
                .product(name: "Connectivity", package: "connectivity"),
            ]),
    ]
)
