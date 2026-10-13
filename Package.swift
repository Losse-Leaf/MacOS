// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LooseLeaf",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LooseLeaf", targets: ["LooseLeaf"])
    ],
    targets: [
        .executableTarget(
            name: "LooseLeaf",
            path: "LooseLeaf",
            exclude: [
                "Info.plist",
                "LooseLeaf.entitlements"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "LooseLeafTests",
            dependencies: ["LooseLeaf"],
            path: "LooseLeafTests"
        )
    ]
)
