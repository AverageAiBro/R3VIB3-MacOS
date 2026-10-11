// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "R3VIB3",
    platforms: [
        .macOS(.v26),
    ],
    targets: [
        .executableTarget(
            name: "R3VIB3",
            path: "LocalTranscribePaste",
            exclude: [
                "Resources/Info.plist",
                "LocalTranscribePaste.entitlements",
            ],
            resources: [
                .process("Resources"),
            ]),
        .testTarget(name: "R3VIB3Tests", dependencies: ["R3VIB3"], path: "Tests")
    ],
    swiftLanguageModes: [.v5]
)
