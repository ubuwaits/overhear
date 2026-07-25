// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Fragmentary",
    platforms: [
        .macOS("14.2")
    ],
    products: [
        .executable(name: "Fragmentary", targets: ["Fragmentary"])
    ],
    targets: [
        .target(
            name: "FragmentaryDSP",
            path: "Sources/FragmentaryDSP",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("AudioToolbox")
            ]
        ),
        .executableTarget(
            name: "Fragmentary",
            dependencies: ["FragmentaryDSP"],
            path: "Sources/Fragmentary",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox")
            ]
        ),
        .testTarget(
            name: "FragmentaryDSPTests",
            dependencies: ["FragmentaryDSP"],
            path: "Tests/FragmentaryDSPTests"
        )
    ]
)
