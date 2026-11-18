// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MedyaCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MedyaCore", targets: ["MedyaCore"])],
    targets: [
        .target(name: "MedyaCore"),
        .testTarget(name: "MedyaCoreTests", dependencies: ["MedyaCore"], resources: [.copy("Fixtures")]),
    ]
)
