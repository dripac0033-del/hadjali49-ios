// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "hadjali49",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "hadjali49",
            targets: ["hadjali49"]
        ),
    ],
    targets: [
        .target(
            name: "hadjali49",
            path: "hadjali49"
        ),
    ]
)
