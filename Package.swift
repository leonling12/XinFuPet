// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "XinFuPet",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "XinFuPet", targets: ["XinFuPet"])],
    targets: [
        .executableTarget(name: "XinFuPet", path: "Sources/XinFuPet")
    ]
)
