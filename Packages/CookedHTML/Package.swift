// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CookedHTML",
    platforms: [
        .iOS(.v15),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CookedHTML", targets: ["CookedHTML"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "CookedHTML",
            dependencies: ["SwiftSoup"]
        ),
        .testTarget(
            name: "CookedHTMLTests",
            dependencies: ["CookedHTML"]
        ),
    ]
)
