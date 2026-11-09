// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Overhear",
    platforms: [
        .macOS("14.2")
    ],
    products: [
        .executable(name: "Overhear", targets: ["Overhear"])
    ],
    targets: [
        .target(
            name: "OverhearDSP",
            path: "Sources/OverhearDSP",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("AudioToolbox")
            ]
        ),
        .executableTarget(
            name: "Overhear",
            dependencies: ["OverhearDSP"],
            path: "Sources/Overhear",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox")
            ]
        ),
        .testTarget(
            name: "OverhearDSPTests",
            dependencies: ["OverhearDSP", "Overhear"],
            path: "Tests/OverhearDSPTests"
        )
    ]
)
