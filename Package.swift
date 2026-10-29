// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SlowQuitGuard",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QuitGuardCore", targets: ["QuitGuardCore"]),
        .executable(name: "SlowQuitGuard", targets: ["SlowQuitGuard"])
    ],
    targets: [
        .target(name: "QuitGuardCore"),
        .executableTarget(name: "SlowQuitGuard", dependencies: ["QuitGuardCore"]),
        .testTarget(name: "QuitGuardCoreTests", dependencies: ["QuitGuardCore"]),
        .testTarget(name: "QuitGuardUITests", dependencies: ["SlowQuitGuard", "QuitGuardCore"])
    ]
)
