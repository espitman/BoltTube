// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BoltTubeMacNative",
    platforms: [
        .macOS(.v14),
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
            ]
        )
    ]
)
