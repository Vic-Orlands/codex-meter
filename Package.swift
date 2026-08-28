// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMeter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexMeter", targets: ["CodexMeter"])
    ],
    targets: [
        .executableTarget(
            name: "CodexMeter",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "CodexMeterTests", dependencies: ["CodexMeter"])
    ],
    swiftLanguageModes: [.v5]
)
