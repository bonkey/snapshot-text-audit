// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "snapshot-text-audit",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "snapshot-text-audit", targets: ["snapshot-text-audit"]),
        .library(name: "SnapshotTextAuditCore", targets: ["SnapshotTextAuditCore"]),
    ],
    targets: [
        .target(name: "SnapshotTextAuditCore"),
        .executableTarget(
            name: "snapshot-text-audit",
            dependencies: ["SnapshotTextAuditCore"]
        ),
    ]
)
