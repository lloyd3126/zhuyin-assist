// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZhuyinAssist",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "GeminiParagraphCorrection", targets: ["ZhuyinAssist"])
    ],
    targets: [
        .executableTarget(name: "ZhuyinAssist", path: "Sources/ZhuyinAssist")
    ]
)
