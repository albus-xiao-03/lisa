// PROOF ONLY — Apps/Proof never ships. Runs one design's nearby proof on this device (plan §8.7, §10.5 N-1): a
// listener under a random Bonjour name, a browser, outgoing and incoming connections with peer-to-peer Wi-Fi, the
// session pipeline on each, deduplication by device ID, per-endpoint backoff, Design A's 15-minute window rotation
// and rejoin trials (at most 9 services × 9 candidates), local-network states, and reconnection after the owner's
// kill or Wi-Fi toggle. Everything runs in the foreground (plan §8.7 Background). Network objects run on the main
// queue, so their handlers are main-actor isolated.

import Foundation
import LisaSyncProtocol
import LisaTrust
import Network

@MainActor
final class ProofNearbyController {
    struct Event: Identifiable, Sendable {
        let id = UUID()
        let monotonicNanoseconds: UInt64
        let text: String
    }

    struct ReconnectObservation: Sendable {
        let trigger: ProofReconnectTrigger
        let peerDeviceID: String
        let downNanoseconds: UInt64
        let authenticatedNanoseconds: UInt64
    }

    enum Failure: Error, Equatable {
        case noDesignBIdentity
    }

    private(set) var events: [Event] = []
    private(set) var lastSessionCode: String?
    var onReport: ((ProofSessionReport) -> Void)?
    var onLocalNetwork: ((ProofLocalNetworkState, String) -> Void)?
    var onDeduplication: ((String) -> Void)?
    var onReconnect: ((ReconnectObservation) -> Void)?
    var onChange: (() -> Void)?

    private let keys: ProofDeviceKeys
    private let roster: ProofRoster
    private let identity: ProofIdentityProvisioner.Provisioned?
    /// Design B's throwaway identity, which no roster lists; presented only under the unenrolled-identity fault.
    private let unenrolledIdentity: ProofIdentityProvisioner.Provisioned?
    private let launchedAt = ProofMonotonicClock.nowNanoseconds()
    private var configuration = ProofNearbyConfiguration()
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var pathMonitor: NWPathMonitor?
    private var ownServiceName = ""
    private var ticker: Task<Void, Never>?
    private var listenerWindow: UInt64 = 0
    private var deduplicator = ProofConnectionDeduplicator()
    private var backoff = ProofEndpointBackoff()
    private var connections: [UUID: NWConnection] = [:]
    private var dialing: Set<String> = []
    private var completedServices: Set<String> = []
    private var servicePeer: [String: String] = [:]
    private var rejoinCandidates: [String: [ProofRosterEntry]] = [:]
    private var downSince: [String: UInt64] = [:]

    init(
        keys: ProofDeviceKeys, roster: ProofRoster, identity: ProofIdentityProvisioner.Provisioned?,
        unenrolledIdentity: ProofIdentityProvisioner.Provisioned? = nil
    ) {
        self.keys = keys
        self.roster = roster
        self.identity = identity
        self.unenrolledIdentity = unenrolledIdentity
    }

    func start(_ configuration: ProofNearbyConfiguration) throws {
        stop()
        self.configuration = configuration
        ownServiceName = ProofServiceName.random()
        try startListener()
        startBrowser()
        startPathMonitor()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                self?.tick()
            }
        }
        log("started design \(configuration.design.rawValue) as \(ownServiceName)")
    }

    func stop() {
        ticker?.cancel()
        listener?.cancel()
        browser?.cancel()
        pathMonitor?.cancel()
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        dialing.removeAll()
        listener = nil
        browser = nil
        pathMonitor = nil
    }

    /// The owner's "reconnect now": forget completed sessions so the browser's peers are dialed again.
    func allowReconnect() {
        completedServices.removeAll()
        tick()
    }

    // MARK: Listener

    private var currentWindow: UInt64 {
        NearbyPairKeys.window(atUnixSeconds: Int64(Date().timeIntervalSince1970))
    }

    private var dialRoster: ProofRoster {
        guard configuration.rejoin,
            let stale = try? ProofRoster(
                setup: roster.setup.withoutDiscoverySecret(), ownDeviceID: roster.ownDeviceID, entries: roster.entries)
        else { return roster }
        return stale
    }

    private func startListener() throws {
        let parameters: NWParameters
        var service: NWListener.Service
        switch configuration.design {
        case .a:
            listenerWindow = currentWindow
            let entries = try DesignAPSKTable.listenerEntries(keys: keys, roster: dialRoster, window: listenerWindow)
            let probe: (@Sendable (Int?) -> Void)? =
                configuration.probeSelectionBlock
                ? { [weak self] hintBytes in
                    Task { @MainActor [weak self] in
                        self?.log(
                            "PSK selection block called on the listener; hint bytes: \(hintBytes.map(String.init) ?? "none")"
                        )
                    }
                } : nil
            parameters = DesignAParameters.make(
                entries: entries, policy: configuration.suitePolicy, selectionProbe: probe)
            service = NWListener.Service(name: ownServiceName, type: DesignADiscovery.serviceType)
            if let secret = dialRoster.setup.discoverySecret {
                let tag = NearbyPairKeys.discoveryTag(secret: secret, window: listenerWindow, device: keys.deviceID)
                service = NWListener.Service(
                    name: ownServiceName, type: DesignADiscovery.serviceType, domain: nil,
                    txtRecord: DesignADiscovery.txtRecord(tag: tag))
            }
            log("listener: \(entries.count) PSK entries for window \(listenerWindow)")
        case .b:
            guard let identity else { throw Failure.noDesignBIdentity }
            parameters = DesignBParameters.make(identity: identity.identity, roster: roster)
            service = NWListener.Service(name: ownServiceName, type: DesignBParameters.serviceType)
        }
        let listener = try NWListener(using: parameters)
        listener.service = service
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.listenerChanged(state) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func listenerChanged(_ state: NWListener.State) {
        log("listener: \(state)")
        if let classified = ProofLocalNetworkObserver.classify(state) {
            onLocalNetwork?(classified, "listener \(state)")
        }
    }

    /// Design A rotates the tag and the PSK entries every window by replacing the listener; established
    /// connections are separate objects and stay up (an assumption X1 observes; docs/DECISIONS.md D-54).
    private func rotateListenerIfNeeded() {
        guard configuration.design == .a, currentWindow != listenerWindow else { return }
        listener?.cancel()
        ownServiceName = ProofServiceName.random()
        do {
            try startListener()
        } catch {
            log("listener rotation failed: \(error)")
        }
    }

    private func accept(_ connection: NWConnection) {
        start(connection, role: .responder, serviceName: nil, pskKind: nil, sessionKeys: keys)
    }

    // MARK: Browser

    private func startBrowser() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let type = configuration.design == .a ? DesignADiscovery.serviceType : DesignBParameters.serviceType
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: nil), using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                self?.log("browser: \(state)")
                if let classified = ProofLocalNetworkObserver.classify(state) {
                    self?.onLocalNetwork?(classified, "browser \(state)")
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] _, changes in
            MainActor.assumeIsolated { self?.browseChanged(changes) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func browseChanged(_ changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            if case .removed(let result) = change, let name = Self.serviceName(result) {
                completedServices.remove(name)
                rejoinCandidates[name] = nil
                if let peer = servicePeer[name] { downSince[peer] = ProofMonotonicClock.nowNanoseconds() }
                log("service lost: \(name)")
            }
        }
        tick()
    }

    private func tick() {
        rotateListenerIfNeeded()
        guard let results = browser?.browseResults else { return }
        for result in results {
            guard let name = Self.serviceName(result), name != ownServiceName, !dialing.contains(name),
                !completedServices.contains(name), backoff.mayAttempt(name)
            else { continue }
            dial(result, serviceName: name)
        }
    }

    private func dial(_ result: NWBrowser.Result, serviceName: String) {
        let sessionKeys: ProofDeviceKeys =
            switch configuration.fault {
            case .unenrolledIdentity: ProofDeviceKeys.unenrolled()
            case .unenrolledOperationKey: keys.withUnenrolledOperationKey()
            default: keys
            }
        switch configuration.design {
        case .a:
            let window = currentWindow
            let peer: ProofRosterEntry?
            if configuration.rejoin {
                var queue = rejoinCandidates[serviceName] ?? dialRoster.activePeers
                peer = queue.isEmpty ? nil : queue.removeFirst()
                rejoinCandidates[serviceName] = queue
            } else {
                peer = DesignADiscovery.peer(for: result, roster: dialRoster, window: window)
            }
            guard let peer else { return }
            do {
                let entry = try DesignAPSKTable.initiatorEntry(
                    keys: sessionKeys, peer: peer, roster: dialRoster, window: window, rejoin: configuration.rejoin)
                let parameters = DesignAParameters.make(entries: [entry], policy: configuration.suitePolicy)
                servicePeer[serviceName] = peer.deviceID.hex
                start(
                    NWConnection(to: result.endpoint, using: parameters), role: .initiator, serviceName: serviceName,
                    pskKind: entry.kind, sessionKeys: sessionKeys)
            } catch {
                log("design A dial to \(serviceName) failed before connecting: \(error)")
            }
        case .b:
            let presented = configuration.fault == .unenrolledIdentity ? unenrolledIdentity : identity
            guard let presented else {
                log(
                    "design B dial to \(serviceName) skipped: no \(configuration.fault == .unenrolledIdentity ? "unenrolled" : "enrolled") identity"
                )
                return
            }
            let parameters = DesignBParameters.make(identity: presented.identity, roster: roster) { [weak self] hex in
                Task { @MainActor [weak self] in
                    self?.log("verify block: \(hex.map { "pinned peer \($0)" } ?? "no roster pin; refused")")
                }
            }
            start(
                NWConnection(to: result.endpoint, using: parameters), role: .initiator, serviceName: serviceName,
                pskKind: nil, sessionKeys: sessionKeys)
        }
    }

    // MARK: Connections and sessions

    private func start(
        _ connection: NWConnection, role: NearbyRole, serviceName: String?, pskKind: DesignAPSKEntry.Kind?,
        sessionKeys: ProofDeviceKeys
    ) {
        let id = UUID()
        connections[id] = connection
        if let serviceName { dialing.insert(serviceName) }
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                self?.connectionChanged(
                    id, connection, state, role: role, serviceName: serviceName, pskKind: pskKind,
                    sessionKeys: sessionKeys)
            }
        }
        connection.start(queue: .main)
    }

    private func connectionChanged(
        _ id: UUID, _ connection: NWConnection, _ state: NWConnection.State, role: NearbyRole, serviceName: String?,
        pskKind: DesignAPSKEntry.Kind?, sessionKeys: ProofDeviceKeys
    ) {
        switch state {
        case .ready:
            runSession(id, connection, role: role, serviceName: serviceName, pskKind: pskKind, sessionKeys: sessionKeys)
        case .waiting(let error):
            log("connection \(role.rawValue) waiting: \(error)")
            if let denied = ProofLocalNetworkObserver.classify(connection.currentPath) {
                onLocalNetwork?(denied, "connection path")
            }
        case .failed(let error):
            // A handshake refusal (no matching PSK, no roster pin) ends here, before any session frame.
            var report = ProofSessionReport(
                design: configuration.design.rawValue, role: role.rawValue,
                harnessRole: configuration.harnessRole.rawValue, fault: configuration.fault.rawValue,
                startedAtNanoseconds: ProofMonotonicClock.nowNanoseconds())
            report.pskIdentityKind = pskKind?.rawValue
            report.refusal = "tls-or-connection-failed: \(error)"
            report.endedAtNanoseconds = report.startedAtNanoseconds
            onReport?(report)
            connection.cancel()
            if let serviceName {
                backoff.recordFailure(serviceName)
                dialing.remove(serviceName)
            }
        case .cancelled:
            connections[id] = nil
            if let serviceName { dialing.remove(serviceName) }
        default:
            break
        }
    }

    private func runSession(
        _ id: UUID, _ connection: NWConnection, role: NearbyRole, serviceName: String?,
        pskKind: DesignAPSKEntry.Kind?, sessionKeys: ProofDeviceKeys
    ) {
        let realSecret = roster.setup.discoverySecret
        let runner = ProofSessionRunner(
            configuration: configuration, roster: roster, keys: sessionKeys,
            handoverSecret: configuration.rejoin ? nil : realSecret, expectedSecret: realSecret)
        let opener = sessionKeys.deviceID
        Task { [weak self] in
            guard let self else { return }
            let report = await runner.run(
                connection: connection, role: role, pskKind: pskKind,
                admit: { outcome in
                    await self.admit(
                        id, peer: outcome.peer.deviceID, openedBy: role == .initiator ? opener : outcome.peer.deviceID)
                },
                stillLive: { await self.isLive(id) })
            self.finished(id, report, serviceName: serviceName)
        }
    }

    private func admit(_ id: UUID, peer: Identifier128, openedBy: Identifier128) -> Bool {
        let session = ProofConnectionDeduplicator.Session(id: id, peer: peer, openedBy: openedBy)
        guard let loser = deduplicator.admit(session) else { return true }
        let survivor = deduplicator.live[peer]
        let text =
            "deduplication: peer \(peer.hex) kept the session opened by \(survivor?.openedBy.hex ?? "?"), "
            + "closed the one opened by \(loser.openedBy.hex)"
        log(text)
        onDeduplication?(text)
        if loser.id != id { connections[loser.id]?.cancel() }
        return loser.id != id
    }

    private func isLive(_ id: UUID) -> Bool {
        deduplicator.live.values.contains { $0.id == id }
    }

    private func finished(_ id: UUID, _ report: ProofSessionReport, serviceName: String?) {
        if let session = deduplicator.live.values.first(where: { $0.id == id }) { deduplicator.remove(session) }
        if let serviceName {
            dialing.remove(serviceName)
            if report.authenticated {
                completedServices.insert(serviceName)
                backoff.recordSuccess(serviceName)
            } else if configuration.rejoin, !(rejoinCandidates[serviceName] ?? []).isEmpty {
                // Try the next candidate pair key on the same service.
            } else {
                backoff.recordFailure(serviceName)
            }
        }
        if report.authenticated, let peer = report.peerDeviceID, let at = report.authenticatedAtNanoseconds,
            configuration.nextReconnectTrigger != .none, !report.closedByDeduplication
        {
            onReconnect?(
                ReconnectObservation(
                    trigger: configuration.nextReconnectTrigger, peerDeviceID: peer,
                    downNanoseconds: downSince[peer] ?? launchedAt, authenticatedNanoseconds: at))
            downSince[peer] = nil
        }
        if let code = report.sessionCode { lastSessionCode = code }
        onReport?(report)
        onChange?()
    }

    // MARK: Path

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            MainActor.assumeIsolated { self?.pathChanged(path) }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor
    }

    private func pathChanged(_ path: NWPath) {
        let now = ProofMonotonicClock.nowNanoseconds()
        log("path: \(path.status) via \(path.availableInterfaces.map(\.name).joined(separator: ","))")
        for peer in Set(servicePeer.values) where downSince[peer] == nil { downSince[peer] = now }
        completedServices.removeAll()
    }

    // MARK: Helpers

    private static func serviceName(_ result: NWBrowser.Result) -> String? {
        if case .service(let name, _, _, _) = result.endpoint { return name }
        return nil
    }

    private func log(_ text: String) {
        events.append(Event(monotonicNanoseconds: ProofMonotonicClock.nowNanoseconds(), text: text))
        if events.count > 500 { events.removeFirst(events.count - 500) }
        onChange?()
    }
}
