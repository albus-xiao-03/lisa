// swift-tools-version: 6.2
// The Lisa Swift package: portable engine, adapters, host runtime and command-line interface.
// Apple application targets live in Apps/ and are not part of this package graph.

import PackageDescription

let package = Package(
    name: "Lisa",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "LisaRedaction", targets: ["LisaRedaction"]),
        .library(name: "LisaTime", targets: ["LisaTime"]),
        .library(name: "LisaDomain", targets: ["LisaDomain"]),
        .library(name: "LisaSecrets", targets: ["LisaSecrets"]),
        .library(name: "LisaLogging", targets: ["LisaLogging"]),
    ],
    targets: [
        .target(name: "LisaRedaction"),
        .target(name: "LisaTime"),
        .target(name: "LisaDomain", dependencies: ["LisaTime", "LisaRedaction"]),
        .target(name: "LisaSecrets", dependencies: ["LisaRedaction"]),
        .target(name: "LisaLogging", dependencies: ["LisaRedaction"]),
    ],
    swiftLanguageModes: [.v6]
)
