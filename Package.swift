// swift-tools-version: 6.2
import PackageDescription

// libtiff, libjpeg-turbo and zstd are built as universal static libraries by Scripts/build-libtiff.sh
// into Vendor/ (docs/TECH_SPEC.md §1). The app links them statically: no dylib ships with it.
let vendor = Context.packageDirectory + "/Vendor"

let package = Package(
    name: "ViVuView",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ViVuView", targets: ["ViVuView"]),
        .executable(name: "vivu-bench", targets: ["ViVuBench"]),
    ],
    targets: [
        .target(
            name: "CTIFFShim",
            cSettings: [.unsafeFlags(["-I\(vendor)/include"])],
            linkerSettings: [
                .unsafeFlags(["-L\(vendor)/lib"]),
                .linkedLibrary("tiff"),
                .linkedLibrary("jpeg"),
                .linkedLibrary("zstd"),
                .linkedLibrary("z"),
            ]
        ),
        .target(
            name: "ViVuCore",
            dependencies: ["CTIFFShim"]
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
