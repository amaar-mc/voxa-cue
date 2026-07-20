// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoxaKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "VoxaCore", targets: ["VoxaCore"]),
        .library(name: "VoxaRuntime", targets: ["VoxaRuntime"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")
    ],
    targets: [
        .target(name: "VoxaCore"),
        .target(
            name: "VoxaRuntime",
            dependencies: [
                "VoxaCore",
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ]
        ),
        .testTarget(name: "VoxaCoreTests", dependencies: ["VoxaCore"]),
        .testTarget(
            name: "VoxaRuntimeTests",
            dependencies: [
                "VoxaRuntime",
                "VoxaCore",
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
