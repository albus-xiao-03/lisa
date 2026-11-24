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
        .library(name: "LisaCrypto", targets: ["LisaCrypto"]),
        .library(name: "LisaDelivery", targets: ["LisaDelivery"]),
        .library(name: "LisaDevices", targets: ["LisaDevices"]),
        .library(name: "LisaOwnerData", targets: ["LisaOwnerData"]),
        .library(name: "LisaIngestion", targets: ["LisaIngestion"]),
        .library(name: "LisaReview", targets: ["LisaReview"]),
        .library(name: "LisaAgenda", targets: ["LisaAgenda"]),
        .library(name: "LisaApplication", targets: ["LisaApplication"]),
        .library(name: "LisaAPIContract", targets: ["LisaAPIContract"]),
        .library(name: "LisaConfig", targets: ["LisaConfig"]),
        .library(name: "LisaClient", targets: ["LisaClient"]),
        .library(name: "LisaPresentation", targets: ["LisaPresentation"]),
        .library(name: "LisaAPI", targets: ["LisaAPI"]),
        .library(name: "LisaAPIServer", targets: ["LisaAPIServer"]),
        .library(name: "LisaRuntime", targets: ["LisaRuntime"]),
        .library(name: "LisaLocalSources", targets: ["LisaLocalSources"]),
        .library(name: "LisaHost", targets: ["LisaHost"]),
        .library(name: "LisaFixtures", targets: ["LisaFixtures"]),
        .library(name: "LisaDemo", targets: ["LisaDemo"]),
        .library(name: "LisaHTTP", targets: ["LisaHTTP"]),
        .library(name: "LisaCurl", targets: ["LisaCurl"]),
        .library(name: "LisaHTTPSources", targets: ["LisaHTTPSources"]),
        .library(name: "LisaCalendarFeeds", targets: ["LisaCalendarFeeds"]),
        .library(name: "LisaNewsFeeds", targets: ["LisaNewsFeeds"]),
        .library(name: "LisaXSource", targets: ["LisaXSource"]),
        .library(name: "LisaDiscordSource", targets: ["LisaDiscordSource"]),
        .library(name: "LisaIMAP", targets: ["LisaIMAP"]),
        .library(name: "LisaSMTP", targets: ["LisaSMTP"]),
        .library(name: "LisaTwilio", targets: ["LisaTwilio"]),
        .library(name: "LisaAPNs", targets: ["LisaAPNs"]),
        .library(name: "LisaOpenAICompatible", targets: ["LisaOpenAICompatible"]),
        // R2 (plan §7.2.1).
        .library(name: "LisaSyncProtocol", targets: ["LisaSyncProtocol"]),
        .library(name: "LisaTrust", targets: ["LisaTrust"]),
        .library(name: "LisaArchive", targets: ["LisaArchive"]),
        .library(name: "LisaMerge", targets: ["LisaMerge"]),
        .executable(name: "lisa", targets: ["LisaCLI"]),
    ],
    dependencies: [
        // Approved by the owner on 2026-11-15 (plan §11, REC-DEP-06).
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "5.1.2"),
        // Approved by the owner on 2026-11-15 (plan §11, REC-DEP-01): the `lisa` command-line interface only.
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
        // Approved by the owner on 2026-11-15 (plan §11, REC-DEP-03 and REC-DEP-04): the network API server only.
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.105.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", exact: "2.37.6"),
    ],
    targets: [
        .target(name: "LisaRedaction"),
        .target(name: "LisaTime"),
        // R2 wire types and canonical encoding (plan §7.2.1, §8.16): the Swift standard library only.
        .target(name: "LisaSyncProtocol"),
        // R2 merge state and rules (plan §7.2.1, §8.3): registers, observed sets, authority, terminal actions.
        .target(name: "LisaMerge", dependencies: ["LisaSyncProtocol"]),
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
        .target(name: "LisaPorts", dependencies: ["LisaDomain", "LisaTime", "LisaRedaction"]),
        .systemLibrary(
            name: "CSQLite", path: "Sources/CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
        .target(name: "LisaSQLite", dependencies: ["CSQLite"]),
        .target(name: "LisaStore", dependencies: ["LisaSQLite", "LisaPorts", "LisaDomain", "LisaTime"]),
        .target(name: "LisaCrypto", dependencies: [.product(name: "Crypto", package: "swift-crypto")]),
        // R2 signatures, token hashing, owner texts and the nearby session layer (plan §7.2.1).
        .target(name: "LisaTrust", dependencies: ["LisaCrypto", "LisaSyncProtocol"]),
        // R2 protected archive format, sealing and opening (plan §7.2.1, §8.6.6).
        .target(name: "LisaArchive", dependencies: ["LisaSyncProtocol", "LisaTrust", "LisaCrypto"]),
        .target(
            name: "LisaDelivery", dependencies: ["LisaTime", "LisaDomain", "LisaLogging", "LisaPolicy", "LisaPorts"]),
        .target(
            name: "LisaDevices", dependencies: ["LisaTime", "LisaDomain", "LisaLogging", "LisaCrypto", "LisaPorts"]),
        .target(name: "LisaOwnerData", dependencies: ["LisaTime", "LisaDomain", "LisaLogging", "LisaPorts"]),
        .target(
            name: "LisaIngestion",
            dependencies: [
                "LisaTime", "LisaDomain", "LisaLogging", "LisaICalendar", "LisaMIME", "LisaFeeds", "LisaHTMLText",
                "LisaPorts",
            ]),
        .target(
            name: "LisaReview",
            dependencies: [
                "LisaTime", "LisaDomain", "LisaLogging", "LisaICalendar", "LisaMatching", "LisaInference", "LisaPorts",
            ]),
        .target(
            name: "LisaAgenda",
            dependencies: [
                "LisaTime", "LisaDomain", "LisaLogging", "LisaPlanning", "LisaPolicy", "LisaRanking",
                "LisaBriefComposer",
                "LisaPorts", "LisaDelivery",
            ]),
        .target(
            name: "LisaApplication",
            dependencies: [
                "LisaTime", "LisaDomain", "LisaLogging", "LisaPorts", "LisaIngestion", "LisaReview", "LisaDelivery",
                "LisaAgenda", "LisaDevices", "LisaOwnerData",
            ]),
        // Foundation only: shared with the iPhone and iPad app (plan §5.1 rule 4).
        .target(name: "LisaAPIContract"),
        .target(name: "LisaConfig", dependencies: ["LisaTime", "LisaDomain", "LisaSecrets"]),
        // Foundation and the contract only, so Apple apps can link it.
        .target(name: "LisaClient", dependencies: ["LisaAPIContract"]),
        .target(name: "LisaPresentation", dependencies: ["LisaClient", "LisaAPIContract"]),
        .target(name: "LisaLocalSources", dependencies: ["LisaDomain", "LisaPorts"]),
        .target(
            name: "LisaRuntime",
            dependencies: [
                "LisaTime", "LisaDomain", "LisaLogging", "LisaPorts", "LisaIngestion", "LisaOwnerData",
                "LisaApplication",
            ]),
        .target(
            name: "LisaHost",
            dependencies: [
                "LisaTime", "LisaDomain", "LisaSecrets", "LisaLogging", "LisaPorts", "LisaStore", "LisaInference",
                "LisaIngestion", "LisaReview", "LisaDelivery", "LisaAgenda", "LisaDevices", "LisaOwnerData",
                "LisaApplication", "LisaRuntime", "LisaAPI", "LisaAPIContract", "LisaLocalSources", "LisaConfig",
                "LisaMIME", "LisaICalendar", "LisaHTTP", "LisaCurl", "LisaCalendarFeeds", "LisaNewsFeeds", "LisaXSource",
                "LisaDiscordSource", "LisaIMAP", "LisaSMTP", "LisaTwilio", "LisaAPNs", "LisaOpenAICompatible",
                "LisaAPIServer", "LisaCrypto",
            ]),
        // Synthetic demonstration data, rooted at Fixtures/ (plan §5.1 row 50).
        .target(
            name: "LisaFixtures", path: "Fixtures", exclude: ["README.md"],
            resources: [.copy("mail"), .copy("calendar"), .copy("feeds"), .copy("demo")]),
        .target(
            name: "LisaDemo",
            dependencies: [
                "LisaTime", "LisaDomain", "LisaSecrets", "LisaPorts", "LisaInference", "LisaDelivery", "LisaDevices",
                "LisaLocalSources", "LisaApplication", "LisaRuntime", "LisaAPIContract", "LisaClient", "LisaHost",
                "LisaFixtures",
            ]),
        // Phase 6: the HTTP client boundary and its libcurl implementation (plan §5.1 rows 21, 32 and 33).
        .target(name: "LisaHTTP"),
        .systemLibrary(name: "CCurl", path: "Sources/CCurl", providers: [.apt(["libcurl4-openssl-dev"])]),
        .target(name: "CCurlShim", dependencies: ["CCurl"]),
        .target(name: "LisaCurl", dependencies: ["CCurl", "CCurlShim", "LisaHTTP"]),
        // Phase 6 connectors and transports (plan §5.1 rows 34–42).
        // Shared, package-internal support for HTTP document sources: address resolution, conditional requests,
        // representation headers, status classification and the pass deadline.
        .target(
            name: "LisaHTTPSources",
            dependencies: ["LisaTime", "LisaRedaction", "LisaDomain", "LisaSecrets", "LisaPorts", "LisaHTTP"]),
        .target(
            name: "LisaCalendarFeeds",
            dependencies: [
                "LisaTime", "LisaDomain", "LisaSecrets", "LisaICalendar", "LisaPorts", "LisaHTTP", "LisaHTTPSources",
            ]),
        .target(
            name: "LisaNewsFeeds",
            dependencies: [
                "LisaTime", "LisaDomain", "LisaSecrets", "LisaHTMLText", "LisaPorts", "LisaHTTP", "LisaHTTPSources",
            ]),
        .target(
            name: "LisaXSource",
            dependencies: ["LisaTime", "LisaRedaction", "LisaDomain", "LisaSecrets", "LisaPorts", "LisaHTTP"]),
        .target(
            name: "LisaDiscordSource",
            dependencies: ["LisaTime", "LisaRedaction", "LisaDomain", "LisaSecrets", "LisaPorts", "LisaHTTP"]),
        .target(
            name: "LisaIMAP",
            dependencies: [
                "LisaTime", "LisaRedaction", "LisaDomain", "LisaSecrets", "LisaPorts", "LisaHTTP", "LisaCurl",
            ]),
        .target(
            name: "LisaSMTP",
            dependencies: [
                "LisaTime", "LisaRedaction", "LisaDomain", "LisaSecrets", "LisaMIME", "LisaPorts", "LisaHTTP",
                "LisaCurl",
            ]),
        .target(
            name: "LisaTwilio",
            dependencies: ["LisaTime", "LisaRedaction", "LisaDomain", "LisaSecrets", "LisaPorts", "LisaHTTP"]),
        .target(
            name: "LisaAPNs",
            dependencies: [
                "LisaTime", "LisaRedaction", "LisaDomain", "LisaSecrets", "LisaCrypto", "LisaPorts", "LisaAPIContract",
                "LisaHTTP",
            ]),
        .target(
            name: "LisaOpenAICompatible", dependencies: ["LisaRedaction", "LisaSecrets", "LisaInference", "LisaHTTP"]),
        // The `lisa` executable (plan §5.1 row 52).
        .executableTarget(
            name: "LisaCLI",
            dependencies: [
                "LisaSecrets", "LisaPorts", "LisaLocalSources", "LisaRuntime", "LisaAPIContract", "LisaClient",
                "LisaConfig", "LisaHost", "LisaDemo", "LisaAPIServer",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),
        .target(
            name: "LisaAPI",
            dependencies: [
                "LisaTime", "LisaDomain", "LisaLogging", "LisaCrypto", "LisaPorts", "LisaAPIContract",
                "LisaApplication",
                "LisaAgenda", "LisaDevices", "LisaOwnerData",
            ]),
        .target(
            name: "LisaAPIServer",
            dependencies: [
                "LisaAPIContract", "LisaLogging",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ]),
        // The owner-verification harness (plan §10.8): tracked, built from a clean checkout, linked by no product.
        .target(
            name: "LisaVerifyKit", dependencies: ["LisaCrypto", "LisaSQLite"], path: "Harness/Sources/LisaVerifyKit"),
        .target(
            name: "LisaVerifyCases", dependencies: ["LisaVerifyKit", "LisaVerifyServers"],
            path: "Harness/Sources/LisaVerifyCases"),
        .executableTarget(
            name: "lisa-verify",
            dependencies: [
                "LisaVerifyKit", "LisaVerifyCases", "LisaVerifyServers",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ], path: "Harness/Sources/lisa-verify"),
        .target(
            name: "LisaVerifyServers",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"), .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ], path: "Harness/Sources/LisaVerifyServers"),
        // The R1 test suite (plan §9, §10; spec §16): every library through its public API, in debug and release.
        .testTarget(
            name: "LisaTests",
            dependencies: [
                "LisaAPI", "LisaAPIContract", "LisaAPIServer", "LisaAPNs", "LisaAgenda", "LisaApplication",
                "LisaBriefComposer", "LisaCalendarFeeds", "LisaClient", "LisaConfig", "LisaCrypto", "LisaCurl",
                "LisaDelivery", "LisaDemo", "LisaDevices", "LisaDiscordSource", "LisaDomain", "LisaFeeds",
                "LisaFixtures", "LisaHTMLText", "LisaHTTP", "LisaHTTPSources", "LisaHost", "LisaICalendar", "LisaIMAP",
                "LisaInference", "LisaIngestion", "LisaLocalSources", "LisaLogging", "LisaMIME", "LisaMatching",
                "LisaNewsFeeds", "LisaOpenAICompatible", "LisaOwnerData", "LisaPlanning", "LisaPolicy", "LisaPorts",
                "LisaPresentation", "LisaRanking", "LisaRedaction", "LisaReview", "LisaRuntime", "LisaSMTP",
                "LisaSQLite", "LisaSecrets", "LisaStore", "LisaTime", "LisaTwilio", "LisaXML", "LisaXSource",
            ]),
    ],
    swiftLanguageModes: [.v6]
)
