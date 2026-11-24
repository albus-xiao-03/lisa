// PROOF ONLY — Apps/Proof never ships. The device facts every result carries (plan §10.6, §10.8): platform, model
// identifier, OS version, the Xcode and SDK the build came from (Xcode writes DTXcode, DTXcodeBuild and DTSDKName
// into the built Info.plist), the app version and the commit the owner built (Info.plist `LisaProofCommit`, set from
// the LISA_PROOF_COMMIT build setting; "unknown" if the owner did not set it).

import Foundation

#if canImport(UIKit)
    import UIKit
#endif

@MainActor
enum ProofDeviceFacts {
    static var platform: String {
        #if os(macOS)
            "macOS"
        #else
            UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        #endif
    }

    static var model: String {
        #if os(macOS)
            sysctlString("hw.model")
        #else
            sysctlString("hw.machine")
        #endif
    }

    static var osVersion: String { ProcessInfo.processInfo.operatingSystemVersionString }

    static var xcodeVersion: String {
        let xcode = info("DTXcode") ?? "unknown"
        let build = info("DTXcodeBuild") ?? "unknown"
        let sdk = info("DTSDKName") ?? "unknown"
        return "DTXcode \(xcode) (\(build)), SDK \(sdk)"
    }

    static var appVersion: String {
        "LisaProof \(info("CFBundleShortVersionString") ?? "?") (\(info("CFBundleVersion") ?? "?"))"
    }

    static var commit: String {
        guard let value = info("LisaProofCommit"), !value.isEmpty, !value.hasPrefix("$(") else { return "unknown" }
        return value
    }

    private static func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
