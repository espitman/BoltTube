// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BoltTubeMacNative",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(
            name: "BoltTubeMacNative",
            targets: ["BoltTubeMacNative"]
        )
    ],
    targets: [
        .executableTarget(
            name: "BoltTubeMacNative",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AVKit"),
                .linkedFramework("AVFoundation")
            ]
        )
    ]
)
