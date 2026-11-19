// The settings behind the connection screen: the Lisa host's address and the owner-supplied TLS trust, kept in a file,
// with the app's transport re-pointed whenever they change.

import Foundation
import LisaAPIContract
import LisaClient

/// Keeps the Lisa host's address and the owner-supplied TLS trust, and points the app's transport at that host
/// (`HostEndpointConfiguring`, NOTIFY-07, API-01).
///
/// - The address and the trust live in one JSON file in the app's client directory. Neither is a secret.
/// - Every change builds the new `URLSessionTransport` first, so a setting this platform cannot use is refused and
///   nothing changes. With owner-supplied trust the transport's server-trust evaluator, built by `makeEvaluator`,
///   trusts only that certificate or certificate authority for the host. Without it the system's trust store and App
///   Transport Security decide. Certificate validation is never turned off.
/// - A settings file that cannot be read or used is reported in `loadProblem`, and requests are refused until the
///   owner sets the host again; the controller never falls back to weaker trust.
@MainActor
public final class HostConnectionController: HostEndpointConfiguring {
    /// Builds the server-trust evaluator for owner-supplied trust; the Apple apps pass a Security-framework evaluator.
    public typealias EvaluatorFactory = @Sendable (HostTrustSettings, HostEndpoint) throws -> any ServerTrustEvaluator

    private static let format = "lisa-host-connection"
    private static let version = 1
    private static let maxFileBytes = 1_048_576

    /// The address requests go to, or `nil` when none is set.
    public private(set) var configuredEndpoint: HostEndpoint?
    /// The owner-supplied trust for the host, or `nil` for the system's trust store.
    public private(set) var trust: HostTrustSettings?
    /// Why the saved settings could not be used at launch; `nil` once the owner sets the host again.
    public private(set) var loadProblem: String?

    private let transport: RetargetableTransport
    private let settingsFile: URL
    private let protection: Data.WritingOptions
    private let configuration: URLSessionTransportConfiguration
    private let makeEvaluator: EvaluatorFactory
    private var current: URLSessionTransport?

    /// Reads the saved settings from `settingsFile` and points `transport` at the saved host, if any.
    ///
    /// - Parameters:
    ///   - transport: the app's transport, which every client request goes through.
    ///   - settingsFile: where the address and the trust are kept.
    ///   - protection: data-protection options for every write of the settings file.
    ///   - configuration: timeouts and limits of the transports built; its evaluator is replaced.
    ///   - makeEvaluator: builds the evaluator for owner-supplied trust.
    public init(
        transport: RetargetableTransport, settingsFile: URL, protection: Data.WritingOptions = [],
        configuration: URLSessionTransportConfiguration = URLSessionTransportConfiguration(),
        makeEvaluator: @escaping EvaluatorFactory
    ) {
        self.transport = transport
        self.settingsFile = settingsFile
        self.protection = protection
        self.configuration = configuration
        self.makeEvaluator = makeEvaluator
        loadSavedSettings()
    }

    /// Sends later requests to `endpoint` with the current trust, and keeps the choice.
    ///
    /// - Throws: when the trust cannot be used for this host or on this platform (for example
    ///   `URLSessionTransportError.customTrustUnavailable` on Linux), or the settings cannot be saved. Nothing changes.
    public func configure(_ endpoint: HostEndpoint) throws {
        try apply(endpoint: endpoint, trust: trust)
    }

    /// Trusts `trust` for the host from now on, or the system's trust store when `nil`, and keeps the choice.
    ///
    /// - Throws: like `configure(_:)`. Nothing changes.
    public func setTrust(_ trust: HostTrustSettings?) throws {
        try apply(endpoint: configuredEndpoint, trust: trust)
    }

    // MARK: - Internals

    private func apply(endpoint: HostEndpoint?, trust: HostTrustSettings?) throws {
        var next: URLSessionTransport?
        if let endpoint { next = try makeTransport(for: endpoint, trust: trust) }
        do {
            try save(
                Document(format: Self.format, version: Self.version, endpoint: endpoint?.description, trust: trust))
        } catch {
            next?.invalidate()
            throw error
        }
        install(next, endpoint: endpoint, trust: trust)
        loadProblem = nil
    }

    private func makeTransport(for endpoint: HostEndpoint, trust: HostTrustSettings?) throws -> URLSessionTransport {
        var settings = configuration
        settings.serverTrustEvaluator = nil
        if let trust { settings.serverTrustEvaluator = try makeEvaluator(trust, endpoint) }
        return try URLSessionTransport(endpoint: endpoint, configuration: settings)
    }

    /// Points the app's transport at `next` and lets the previous transport finish the requests it is sending.
    private func install(_ next: URLSessionTransport?, endpoint: HostEndpoint?, trust: HostTrustSettings?) {
        transport.retarget(to: next)
        current?.invalidate()
        current = next
        configuredEndpoint = endpoint
        self.trust = trust
    }

    private func loadSavedSettings() {
        guard FileManager.default.fileExists(atPath: settingsFile.path) else { return }
        guard let data = try? Data(contentsOf: settingsFile), data.count <= Self.maxFileBytes,
            let document = try? JSONDecoder().decode(Document.self, from: data), document.format == Self.format,
            document.version == Self.version
        else {
            loadProblem = "The saved connection settings could not be read. Enter your Lisa host's address again."
            return
        }
        var endpoint: HostEndpoint?
        if let text = document.endpoint {
            do throws(HostEndpointError) {
                endpoint = try HostEndpoint(parsing: text)
            } catch {
                loadProblem = "The saved host address can't be used: \(error). Enter it again."
                return
            }
        }
        var next: URLSessionTransport?
        do {
            if let endpoint { next = try makeTransport(for: endpoint, trust: document.trust) }
        } catch {
            loadProblem = "The saved connection settings can't be used on this device: \(error)."
            return
        }
        install(next, endpoint: endpoint, trust: document.trust)
    }

    private func save(_ document: Document) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        try FileManager.default.createDirectory(
            at: settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try data.write(to: settingsFile, options: protection.intersection(.fileProtectionMask).union(.atomic))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsFile.path)
    }

    /// The settings file: a format header, the address and the trust.
    private struct Document: Codable {
        var format: String
        var version: Int
        var endpoint: String?
        var trust: HostTrustSettings?
    }
}
