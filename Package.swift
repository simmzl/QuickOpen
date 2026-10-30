// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuickOpen",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "QuickOpen", targets: ["QuickOpen"])
    ],
    targets: [
        .executableTarget(
            name: "QuickOpen",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(
            name: "QuickOpenTests",
            dependencies: ["QuickOpen"]
        )
    ],
    swiftLanguageModes: [.v5]
)
