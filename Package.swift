// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LooseLeaf",
    // 注：本工程暂无 .lproj 本地化资源目录（界面文案直接内联在 Swift 中），
    // 因此**不声明** defaultLocalization —— 声明一个不存在的本地化会让
    // Bundle.module 的 localizedString 行为与预期不符。
    // 需要多语言时：新增 Resources/zh-Hans.lproj/Localizable.strings 后再恢复该声明。
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
                "LooseLeaf.entitlements",
                // UI 自动化测试专用权限文件，仅供 xcodebuild test 使用
                "LooseLeafUITest.entitlements"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "LooseLeafTests",
            dependencies: ["LooseLeaf"],
            path: "LooseLeafTests",
            // 快照基准图是测试夹具，不是可执行资源：显式排除避免 SPM 报「未处理文件」
            exclude: ["__Snapshots__"]
        )
    ]
)
