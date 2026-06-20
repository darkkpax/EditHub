// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EditHub",
    platforms: [
        .macOS(.v26)
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
