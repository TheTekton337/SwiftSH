// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftSH",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
	.library(
	    name: "CSwiftSH",
	    targets: ["CSwiftSH"]),
        .library(
            name: "SwiftSH",
            targets: ["SwiftSH"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(name: "CSSH", url: "https://github.com/TheTekton337/Libssh2Prebuild.git", from: "1.11.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
	.target(
	    name: "CSwiftSH",
	    dependencies: ["CSSH"]),
        .target(
            name: "SwiftSH",
            dependencies: ["CSSH", "CSwiftSH"]),
        .testTarget(
            name: "SwiftSHTests",
            dependencies: ["SwiftSH"],
            path: "SwiftSH Integration Tests"
        ),
    ]
)
