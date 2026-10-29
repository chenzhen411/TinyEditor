// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "TinyEditor", platforms: [.macOS(.v13)], products: [.executable(name: "TinyEditor", targets: ["TinyEditor"])], targets: [.executableTarget(name: "TinyEditor", path: "Sources/TinyEditor"), .testTarget(name: "TinyEditorTests", dependencies: ["TinyEditor"])])
