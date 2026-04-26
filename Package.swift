// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AutoEnableElgatoLight",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "AutoEnableElgatoLightCore",
            targets: ["AutoEnableElgatoLightCore"]
        ),
        .executable(
            name: "AutoEnableElgatoLight",
            targets: ["AutoEnableElgatoLightApp"]
        ),
        .executable(
            name: "AutoEnableElgatoLightDiagnostics",
            targets: ["AutoEnableElgatoLightDiagnostics"]
        )
    ],
    targets: [
        .target(
            name: "AutoEnableElgatoLightCore"
        ),
        .executableTarget(
            name: "AutoEnableElgatoLightApp",
            dependencies: ["AutoEnableElgatoLightCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "AutoEnableElgatoLightDiagnostics",
            dependencies: ["AutoEnableElgatoLightCore"]
        ),
        .testTarget(
            name: "AutoEnableElgatoLightCoreTests",
            dependencies: ["AutoEnableElgatoLightCore"],
            swiftSettings: [
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
                ]),
                .linkedFramework("Testing")
            ]
        )
    ]
)
