// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "IconPicker",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "IconPicker",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/IconPicker",
            linkerSettings: [
                // Sparkle.framework is embedded in Contents/Frameworks of the .app bundle.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
    ]
)
