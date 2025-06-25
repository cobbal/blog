// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "orb",
    targets: [
        .executableTarget(
            name: "orb",
            path: ".",
            sources: ["orb.swift"]
        )
    ]
)
