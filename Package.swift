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
        .library(name: "LisaICalendar", targets: ["LisaICalendar"]),
        .library(name: "LisaMIME", targets: ["LisaMIME"]),
        .library(name: "LisaXML", targets: ["LisaXML"]),
        .library(name: "LisaFeeds", targets: ["LisaFeeds"]),
        .library(name: "LisaHTMLText", targets: ["LisaHTMLText"]),
        .library(name: "LisaPlanning", targets: ["LisaPlanning"]),
        .library(name: "LisaPolicy", targets: ["LisaPolicy"]),
        .library(name: "LisaMatching", targets: ["LisaMatching"]),
        .library(name: "LisaRanking", targets: ["LisaRanking"]),
        .library(name: "LisaBriefComposer", targets: ["LisaBriefComposer"]),
        .library(name: "LisaInference", targets: ["LisaInference"]),
        .library(name: "LisaPorts", targets: ["LisaPorts"]),
        .library(name: "LisaSQLite", targets: ["LisaSQLite"]),
        .library(name: "LisaStore", targets: ["LisaStore"]),
    ],
    targets: [
        .target(name: "LisaRedaction"),
        .target(name: "LisaTime"),
        .target(name: "LisaDomain", dependencies: ["LisaTime", "LisaRedaction"]),
        .target(name: "LisaSecrets", dependencies: ["LisaRedaction"]),
        .target(name: "LisaLogging", dependencies: ["LisaRedaction"]),
        .target(name: "LisaICalendar", dependencies: ["LisaTime"]),
        .target(
            name: "LisaMIME", dependencies: ["LisaTime"],
            linkerSettings: [.linkedLibrary("iconv", .when(platforms: [.macOS, .iOS]))]),
        .systemLibrary(
            name: "CLibXML2", path: "Sources/CLibXML2", pkgConfig: "libxml-2.0",
            providers: [.apt(["libxml2-dev"]), .brew(["libxml2"])]),
        .target(name: "LisaXML", dependencies: ["CLibXML2"]),
        .target(name: "LisaFeeds", dependencies: ["LisaXML", "LisaTime"]),
        .target(name: "LisaHTMLText", dependencies: ["LisaXML"]),
        .target(name: "LisaPlanning", dependencies: ["LisaDomain", "LisaTime"]),
        .target(name: "LisaPolicy", dependencies: ["LisaDomain", "LisaTime"]),
        .target(name: "LisaMatching", dependencies: ["LisaDomain", "LisaTime"]),
        .target(name: "LisaRanking", dependencies: ["LisaDomain", "LisaTime"]),
        .target(name: "LisaBriefComposer", dependencies: ["LisaDomain", "LisaTime"]),
        .target(name: "LisaInference", dependencies: ["LisaDomain", "LisaTime"]),
        .target(name: "LisaPorts", dependencies: ["LisaDomain", "LisaTime"]),
        .systemLibrary(
            name: "CSQLite", path: "Sources/CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
        .target(name: "LisaSQLite", dependencies: ["CSQLite"]),
        .target(name: "LisaStore", dependencies: ["LisaSQLite", "LisaPorts", "LisaDomain", "LisaTime"]),
    ],
    swiftLanguageModes: [.v6]
)
