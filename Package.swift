// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ViVuView",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ViVuView", targets: ["ViVuView"]),
        .executable(name: "vivu-bench", targets: ["ViVuBench"]),
    ],
    targets: [
        .target(
            name: "ViVuCore"
        ),
        .target(
            name: "ViVuRender",
            dependencies: ["ViVuCore"]
        ),
        .executableTarget(
            name: "ViVuView",
            dependencies: ["ViVuCore", "ViVuRender"]
        ),
        .executableTarget(
            name: "ViVuBench",
            dependencies: ["ViVuCore"]
        ),
        .testTarget(
            name: "ViVuCoreTests",
            dependencies: ["ViVuCore"]
        ),
        .testTarget(
            name: "ViVuRenderTests",
            dependencies: ["ViVuRender"]
        ),
    ]
)
