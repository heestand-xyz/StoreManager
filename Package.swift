// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "StoreManager",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
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
