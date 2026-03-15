// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MuniMetadonnees",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MuniMetadonneesCore", targets: ["MuniMetadonneesCore"]),
        .library(name: "MuniMetadonneesInterop", targets: ["MuniMetadonneesInterop"]),
        .executable(name: "muni-metadonnees-cli", targets: ["MuniMetadonneesCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.7.0"),
        .package(url: "https://github.com/Macthieu/OrchivisteKit.git", exact: "0.2.0")
    ],
    targets: [
        .target(name: "MuniMetadonneesCore"),
        .target(
            name: "MuniMetadonneesInterop",
            dependencies: [
                "MuniMetadonneesCore",
                .product(name: "OrchivisteKitContracts", package: "OrchivisteKit")
            ]
        ),
        .executableTarget(
            name: "MuniMetadonneesCLI",
            dependencies: [
                "MuniMetadonneesInterop",
                .product(name: "OrchivisteKitContracts", package: "OrchivisteKit"),
                .product(name: "OrchivisteKitInterop", package: "OrchivisteKit")
            ]
        ),
        .testTarget(
            name: "MuniMetadonneesTests",
            dependencies: [
                "MuniMetadonneesCore",
                "MuniMetadonneesInterop",
                .product(name: "OrchivisteKitContracts", package: "OrchivisteKit"),
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)
