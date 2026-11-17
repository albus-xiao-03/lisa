// Readiness checks for `lisa doctor`: the network library, each source's adapter, the model provider and the live
// delivery adapters, built and checked without contacting any service or sending anything.

import Foundation
import LisaAPNs
import LisaPorts

/// One readiness check.
public struct HostDiagnostic: Hashable, Sendable, Encodable {
    public var name: String
    public var ok: Bool
    public var detail: String

    public init(name: String, ok: Bool, detail: String) {
        self.name = name
        self.ok = ok
        self.detail = detail
    }
}

/// Checks what a host with these settings could do, without opening its data directory.
public enum HostDiagnostics {
    public static func check(settings: HostSettings, platform: HostPlatform) -> [HostDiagnostic] {
        let adapters = HostAdapters(settings: settings, platform: platform)
        var checks: [HostDiagnostic] = []
        switch platform.network.library {
        case .success(let library):
            checks.append(HostDiagnostic(name: "network", ok: true, detail: library.summary))
        case .failure(let error):
            checks.append(
                HostDiagnostic(
                    name: "network", ok: false, detail: "libcurl is unavailable, so no network adapter works: \(error)")
            )
        }
        for source in settings.sources where source.enabled {
            let name = "source \(source.key)"
            switch adapters.connector(for: source.access) {
            case .failure(let reason):
                checks.append(
                    HostDiagnostic(
                        name: name, ok: false,
                        detail: "the \(source.access.adapterName) adapter cannot be used: \(reason)"))
            case .success(let connector):
                do {
                    try connector.validateConfiguration()
                    checks.append(
                        HostDiagnostic(
                            name: name, ok: true,
                            detail: "\(source.access.adapterName): configuration and secrets check out (the service "
                                + "itself is contacted only when the source synchronizes)"))
                } catch {
                    checks.append(
                        HostDiagnostic(name: name, ok: false, detail: "\(source.access.adapterName): \(error)"))
                }
            }
        }
        let (provider, note) = adapters.modelProvider()
        if let note {
            checks.append(HostDiagnostic(name: "model", ok: false, detail: note))
        } else if let provider {
            let descriptor = provider.descriptor
            checks.append(
                HostDiagnostic(
                    name: "model", ok: true,
                    detail: "\(descriptor.name) (\(descriptor.location.rawValue)), data sharing "
                        + "\(settings.dataSharing.rawValue)"))
        } else {
            checks.append(HostDiagnostic(name: "model", ok: true, detail: "no model: items needing one wait"))
        }
        let delivery = settings.ownerSettings.delivery
        let modes =
            "email \(delivery.emailMode.rawValue), calls \(delivery.callMode.rawValue), push "
            + delivery.pushMode.rawValue
        do {
            _ = try adapters.liveTransports()
            let anyLive = [delivery.emailMode, delivery.callMode, delivery.pushMode].contains(.live)
            checks.append(
                HostDiagnostic(
                    name: "delivery", ok: true,
                    detail: modes
                        + (anyLive
                            ? "; the live adapters are ready (nothing is sent by this check)"
                            : "; nothing is sent until a channel is set to live")))
        } catch {
            checks.append(HostDiagnostic(name: "delivery", ok: false, detail: "\(modes); \(error)"))
        }
        if let apns = settings.deliveryAdapters.apns {
            if apns.credentials.isEmpty {
                checks.append(
                    HostDiagnostic(
                        name: "apns", ok: delivery.pushMode != .live,
                        detail: "no APNs environment is enabled, so remote pushes are not possible"))
            } else {
                switch HostAdapters.pushTransport(
                    apns, secrets: platform.secrets, clock: platform.clock, network: platform.network)
                {
                case .success(let transport):
                    for status in transport.environmentStatus {
                        checks.append(
                            HostDiagnostic(
                                name: "apns \(status.environment.rawValue)", ok: status.http2Only,
                                detail: "\(status.endpoint), key \(status.keyID), \(status.transportSummary)"))
                    }
                case .failure(let reason):
                    checks.append(HostDiagnostic(name: "apns", ok: false, detail: reason.description))
                }
            }
        }
        return checks
    }
}
