// libcurl's process-wide initialization and the run-time capabilities of the library actually loaded.

import CCurl
import Foundation

/// Why libcurl could not be used.
public struct CurlSetupError: Error, Hashable, Sendable, CustomStringConvertible {
    public let description: String

    init(_ description: String) { self.description = description }
}

/// The libcurl library loaded at run time.
public struct CurlLibraryInfo: Hashable, Sendable {
    /// Such as `8.14.1`.
    public let version: String
    /// `major << 16 | minor << 8 | patch`.
    public let versionNumber: UInt32
    /// Such as `OpenSSL/3.5.7`.
    public let tlsLibrary: String?
    /// Such as `1.64.0`, when built with nghttp2.
    public let nghttp2Version: String?
    public let hasHTTP2: Bool
    public let hasTLS: Bool
    public let isThreadSafe: Bool
    /// Lowercase protocol names, such as `https`, `imaps` and `smtps`.
    public let protocols: Set<String>

    /// HTTP/2-only requests use `CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE`, which offers only `h2` in TLS ALPN from
    /// libcurl 8.10.0; older versions could fall back to HTTP/1.1.
    public var supportsHTTP2Only: Bool {
        hasHTTP2 && hasTLS && versionNumber >= 0x08_0A_00 && protocols.contains("https")
    }

    public var summary: String {
        var parts = ["libcurl \(version)"]
        if let tlsLibrary { parts.append(tlsLibrary) }
        if let nghttp2Version { parts.append("nghttp2 \(nghttp2Version)") }
        parts.append(supportsHTTP2Only ? "HTTP/2-only requests available" : "HTTP/2-only requests unavailable")
        return parts.joined(separator: ", ")
    }
}

/// libcurl's global state. `curl_global_init` runs once, before any other libcurl call.
public enum CurlRuntime {
    private static let initialization: Result<CurlLibraryInfo, CurlSetupError> = {
        let code = curl_global_init(Int(CURL_GLOBAL_ALL))
        guard code == CURLE_OK else {
            return .failure(
                CurlSetupError("libcurl could not be initialized: \(String(cString: curl_easy_strerror(code)))"))
        }
        // The newest field read (nghttp2_version) arrived with CURLVERSION_SIXTH; libcurl returns its full structure.
        guard let data = curl_version_info(CURLVERSION_SIXTH)?.pointee else {
            return .failure(CurlSetupError("libcurl did not report its version"))
        }
        var protocols: Set<String> = []
        if var cursor = data.protocols {
            while let name = cursor.pointee {
                protocols.insert(String(cString: name).lowercased())
                cursor = cursor.advanced(by: 1)
            }
        }
        let features = Int32(data.features)
        let info = CurlLibraryInfo(
            version: data.version.map { String(cString: $0) } ?? "unknown", versionNumber: UInt32(data.version_num),
            tlsLibrary: data.ssl_version.map { String(cString: $0) },
            nghttp2Version: data.nghttp2_version.map { String(cString: $0) },
            hasHTTP2: features & Int32(CURL_VERSION_HTTP2) != 0, hasTLS: features & Int32(CURL_VERSION_SSL) != 0,
            isThreadSafe: features & Int32(CURL_VERSION_THREADSAFE) != 0, protocols: protocols)
        guard info.isThreadSafe else {
            return .failure(CurlSetupError("\(info.summary) is not thread-safe, which Lisa requires"))
        }
        return .success(info)
    }()

    /// The loaded library, after making sure libcurl is initialized.
    public static func library() throws(CurlSetupError) -> CurlLibraryInfo {
        try initialization.get()
    }
}
