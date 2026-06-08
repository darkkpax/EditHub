// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EditHub",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "EditHub", targets: ["EditHub"])
    ],
    targets: [
        .executableTarget(
            name: "EditHub",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        )
    ]
)
