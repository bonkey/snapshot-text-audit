// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "snapshot-text-audit",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "snapshot-text-audit", targets: ["snapshot-text-audit"]),
        .library(name: "SnapshotTextAuditCore", targets: ["SnapshotTextAuditCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .target(name: "SnapshotTextAuditCore", dependencies: ["Yams"]),
        .executableTarget(
            name: "snapshot-text-audit",
            dependencies: ["SnapshotTextAuditCore"]
        ),
        .testTarget(
            name: "SnapshotTextAuditCoreTests",
            dependencies: ["SnapshotTextAuditCore"]
        ),
    ]
)
