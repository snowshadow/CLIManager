// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CLIManager",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CLIManagerCore", targets: ["CLIManagerCore"]),
        .executable(name: "CLIManagerApp", targets: ["CLIManagerApp"]),
        .executable(name: "CLIManagerCLI", targets: ["CLIManagerCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "CLIManagerCore"
        ),
        .executableTarget(
            name: "CLIManagerApp",
            dependencies: [
                "CLIManagerCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .executableTarget(
            name: "CLIManagerCLI",
            dependencies: ["CLIManagerCore"]
        ),
        .testTarget(
            name: "CLIManagerCoreTests",
            dependencies: ["CLIManagerCore"]
        )
    ]
)
