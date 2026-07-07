// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AutoInputSwitcher",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "AutoInputSwitcherCore",
            targets: ["AutoInputSwitcherCore"]
        ),
        .executable(
            name: "AutoInputSwitcher",
            targets: ["AutoInputSwitcher"]
        ),
        .executable(
            name: "AutoInputSwitcherCoreChecks",
            targets: ["AutoInputSwitcherCoreChecks"]
        )
    ],
    targets: [
        .target(
            name: "AutoInputSwitcherCore"
        ),
        .executableTarget(
            name: "AutoInputSwitcher",
            dependencies: ["AutoInputSwitcherCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .executableTarget(
            name: "AutoInputSwitcherCoreChecks",
            dependencies: ["AutoInputSwitcherCore"]
        )
    ]
)
