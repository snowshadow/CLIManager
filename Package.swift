// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CLIManager",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CLIManagerCore", targets: ["CLIManagerCore"]),
        .executable(name: "CLIManagerApp", targets: ["CLIManagerApp"])
    ],
    targets: [
        .target(
            name: "CLIManagerCore"
        ),
        .executableTarget(
            name: "CLIManagerApp",
            dependencies: ["CLIManagerCore"]
        ),
        .testTarget(
            name: "CLIManagerCoreTests",
            dependencies: ["CLIManagerCore"]
        )
    ]
)
