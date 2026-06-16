// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BoardClip",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "BoardClip", targets: ["BoardClip"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "BoardClip",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/BoardClip"
        )
    ],
    swiftLanguageModes: [.v5]
)
