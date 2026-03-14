// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MuniMetadonnees",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MuniMetadonneesCore", targets: ["MuniMetadonneesCore"]),
        .executable(name: "muni-metadonnees-cli", targets: ["MuniMetadonneesCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.7.0")
    ],
    targets: [
        .target(name: "MuniMetadonneesCore"),
        .executableTarget(name: "MuniMetadonneesCLI", dependencies: ["MuniMetadonneesCore"]),
        .testTarget(
            name: "MuniMetadonneesTests",
            dependencies: [
                "MuniMetadonneesCore",
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)
