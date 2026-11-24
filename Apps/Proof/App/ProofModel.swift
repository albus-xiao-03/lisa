// PROOF ONLY — Apps/Proof never ships. The proof app's state: this device's proof identity, the proof roster the
// owner builds, Design B's identity, the run context from `lisa-verify pair-session`, the nearby controller, the
// fetch probe runs and the E-2 check, with every observation appended to the run's evidence file as it happens.

import Foundation
import LisaSyncProtocol
import LisaTrust
import Observation

@MainActor
@Observable
final class ProofModel {
    static let labelKey = "proof.label"
    static let pinKey = "proof.designB.pin"

    var keys: ProofDeviceKeys?
    var setup: ProofSetupText?
    var peerCards: [ProofDeviceCard] = []
    var inactive: Set<String> = []
    var label = UserDefaults.standard.string(forKey: ProofModel.labelKey) ?? "" {
        didSet { UserDefaults.standard.set(label, forKey: Self.labelKey) }
    }
    var designBPin: Digest256?
    var designBSteps: [String: String] = [:]
    var identity: ProofIdentityProvisioner.Provisioned?
    /// Design B's throwaway identity for the unenrolled-identity fault; its pin never goes into a card.
    var unenrolledIdentity: ProofIdentityProvisioner.Provisioned?
    var context = ProofRunContext.load() {
        didSet { context.save() }
    }
    var nearbyConfiguration = ProofNearbyConfiguration()
    var nearbyRunning = false
    var nearbyEvents: [ProofNearbyController.Event] = []
    var sessionCode: String?
    var localNetworkState: ProofLocalNetworkState?
    var message = ""
    var fetchInputs: [String: String] = [:]
    var fetchSummaries: [String: String] = [:]
    var ownerObservations: [String: ProofStatus] = [:]
    var results: [ProofResultRecord] = []

    private let rosterStore = ProofRosterStore()
    private var controller: ProofNearbyController?
    private var startedAt = (wall: ProofEvidenceMapping.wallClock(), monotonic: ProofMonotonicClock.nowNanoseconds())

    init() {
        do {
            keys = try ProofDeviceKeys.loadOrCreate()
        } catch {
            message = "Proof keys unavailable: \(error)"
        }
        setup = try? rosterStore.setup()
        peerCards = rosterStore.peerCards()
        inactive = rosterStore.inactiveDeviceIDs()
        designBPin = UserDefaults.standard.string(forKey: Self.pinKey).flatMap { try? Digest256(hex: $0) }
        for probeCase in ProbeCase.all {
            for subcase in probeCase.subcases { fetchInputs[probeCase.id + "/" + subcase.id] = subcase.suggestion }
        }
        refreshResults()
    }

    // MARK: Proof roster

    var ownCard: ProofDeviceCard? {
        guard let keys, !label.isEmpty else { return nil }
        return try? ProofDeviceCard(
            deviceID: keys.deviceID, label: label, operationKey: keys.operationSigner.verifier,
            agreementKey: keys.agreementKey.publicKey, tlsKeySHA256: designBPin)
    }

    var roster: ProofRoster? {
        guard let setup, let own = ownCard else { return nil }
        let cards = [own] + peerCards.filter { $0.deviceID != own.deviceID }
        return try? ProofRoster(
            setup: setup, ownDeviceID: own.deviceID,
            entries: cards.map { ProofRosterEntry(card: $0, active: !inactive.contains($0.deviceID.hex)) })
    }

    func generateSetup() {
        perform("setup") {
            let generated = ProofSetupText.generate()
            try rosterStore.saveSetup(generated)
            setup = generated
        }
    }

    func enterSetup(_ text: String) {
        perform("setup") {
            let entered = try ProofSetupText(text: text)
            try rosterStore.saveSetup(entered)
            setup = entered
        }
    }

    func addPeerCard(_ text: String) {
        perform("peer card") {
            try rosterStore.addPeerCard(try ProofDeviceCard(text: text))
            peerCards = rosterStore.peerCards()
        }
    }

    func setActive(_ active: Bool, card: ProofDeviceCard) {
        rosterStore.setActive(active, deviceIDHex: card.deviceID.hex)
        inactive = rosterStore.inactiveDeviceIDs()
    }

    func provisionDesignB() {
        do {
            let provisioned = try ProofIdentityProvisioner.provision()
            identity = provisioned
            designBPin = provisioned.spkiSHA256
            designBSteps = provisioned.steps
            UserDefaults.standard.set(provisioned.spkiSHA256.hex, forKey: Self.pinKey)
            message = "Design B identity ready; give the peers this device's updated card."
        } catch ProofIdentityProvisioner.Failure.step(let step, let steps) {
            designBSteps = steps
            message = "Design B identity failed at \(step)"
        } catch {
            message = "Design B identity failed: \(error)"
        }
    }

    // MARK: Nearby proof

    func startNearby() {
        guard let keys, let roster else {
            message = "Complete the proof roster first."
            return
        }
        guard context.hasValidRunID, context.hasValidCaseID else {
            message = "Enter the run ID and case ID that lisa-verify pair-session printed."
            return
        }
        if nearbyConfiguration.design == .b, identity == nil { provisionDesignB() }
        if nearbyConfiguration.design == .b, identity == nil { return }
        if nearbyConfiguration.design == .b, nearbyConfiguration.fault == .unenrolledIdentity, unenrolledIdentity == nil
        {
            do {
                unenrolledIdentity = try ProofIdentityProvisioner.provision(.unenrolled)
            } catch {
                message = "The throwaway Design B identity failed: \(error)"
                return
            }
        }
        let controller = ProofNearbyController(
            keys: keys, roster: roster, identity: identity, unenrolledIdentity: unenrolledIdentity)
        controller.onReport = { [weak self] report in self?.recordSession(report) }
        controller.onReconnect = { [weak self] observation in
            guard let self else { return }
            append(ProofEvidenceMapping.reconnect(observation, configuration: nearbyConfiguration, context: context))
        }
        controller.onDeduplication = { [weak self] text in
            guard let self else { return }
            append(ProofEvidenceMapping.deduplication(text, configuration: nearbyConfiguration, context: context))
        }
        controller.onLocalNetwork = { [weak self] state, detail in
            guard let self else { return }
            localNetworkState = state
            if let entry = ProofEvidenceMapping.localNetwork(state, detail: detail, context: context) { append(entry) }
        }
        controller.onChange = { [weak self, weak controller] in
            guard let self, let controller else { return }
            nearbyEvents = controller.events
            sessionCode = controller.lastSessionCode
        }
        do {
            try controller.start(nearbyConfiguration)
            self.controller = controller
            nearbyRunning = true
            startedAt = (ProofEvidenceMapping.wallClock(), ProofMonotonicClock.nowNanoseconds())
        } catch {
            message = "Nearby proof did not start: \(error)"
        }
    }

    func stopNearby() {
        controller?.stop()
        controller = nil
        nearbyRunning = false
    }

    func reconnectNow() {
        controller?.allowReconnect()
    }

    func recordPromptObservation() {
        if let entry = ProofEvidenceMapping.prompt(context: context) { append(entry) }
    }

    /// Writes this cell's record (case@role, design) from everything observed so far.
    func finishCell() {
        guard let store = store() else { return }
        let record = ProofCellAggregator.nearbyRecord(
            design: nearbyConfiguration.design, configuration: nearbyConfiguration, context: context,
            evidence: store.evidence(), startedAt: startedAt)
        perform("result") { try store.append(record) }
        refreshResults()
    }

    private func recordSession(_ report: ProofSessionReport) {
        for entry in ProofEvidenceMapping.entries(for: report, configuration: nearbyConfiguration, context: context) {
            append(entry)
        }
    }

    // MARK: Fetch probe (E-1) and E-2

    func runFetch(_ probeCase: ProbeCase, _ subcase: ProbeSubcase) async {
        let key = probeCase.id + "/" + subcase.id
        guard let text = fetchInputs[key], !text.isEmpty else {
            fetchSummaries[key] = "enter the owner's URL or name first"
            return
        }
        if probeCase.id.hasSuffix("FETCH-09") {
            let report = await ProbePlatformFacts.run(name: text)
            var entry = evidence(
                caseID: probeCase.id, check: subcase.id, status: .pass, observed: "platform facts recorded")
            entry.platform = report
            append(entry)
            fetchSummaries[key] = "recorded on \(report.interface)"
            return
        }
        guard let url = URL(string: text) else {
            fetchSummaries[key] = "not a URL"
            return
        }
        let trace = await ProbeFetchRunner.fetch(url)
        let (status, summary) = ProofFetchCaseEvaluator.evaluate(trace, subcase: subcase, caseID: probeCase.id)
        var entry = evidence(caseID: probeCase.id, check: subcase.id, status: status, observed: summary)
        entry.fetch = trace
        append(entry)
        fetchSummaries[key] = "\(status.rawValue): \(summary)"
    }

    func finishFetchCase(_ probeCase: ProbeCase) {
        guard let store = store() else { return }
        let record = ProofFetchCaseEvaluator.record(
            for: probeCase, evidence: store.evidence(), ownerObservation: ownerObservations[probeCase.id],
            context: context, startedAt: startedAt)
        perform("result") { try store.append(record) }
        refreshResults()
    }

    func runE2() {
        guard let store = store() else { return }
        let checks = E2ModuleSmokeCheck.run()
        let passed = checks.values.allSatisfy { $0 }
        let record = ProofCellAggregator.record(
            caseID: E2ModuleSmokeCheck.caseID(platform: ProofDeviceFacts.platform), context: context,
            configuration: ["scheme": "LisaProof"],
            providerInterface: "Apple SDK build of LisaTrust, LisaSyncProtocol, LisaCrypto (swift-crypto), LisaHTTP",
            assumptions: [
                "the build-log digest and destination are attached by the harness from the owner's Xcode build"
            ],
            requiredEvidence: ["Xcode version", "scheme", "destination", "build-log digest"],
            expected: "the portable modules build, link and run on this platform",
            observed: checks.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; "),
            status: passed ? .pass : .fail,
            cause: passed ? "built, launched and exercised on this device" : "a module check failed at run time",
            design: nil, pairSession: nil,
            checks: checks.sorted { $0.key < $1.key }.map {
                ProofResultRecord.Check(
                    id: $0.key, status: $0.value ? .pass : .fail, observed: String($0.value), evidenceEntries: 0)
            }, startedAt: (ProofEvidenceMapping.wallClock(), ProofMonotonicClock.nowNanoseconds()))
        perform("result") { try store.append(record) }
        refreshResults()
    }

    // MARK: Store

    func exportURLs() -> [URL] {
        guard let store = store() else { return [] }
        return [store.url(of: ProofResultStore.resultsFile), store.url(of: ProofResultStore.evidenceFile)]
    }

    private func refreshResults() {
        results = store(quiet: true)?.results() ?? []
    }

    private func store(quiet: Bool = false) -> ProofResultStore? {
        guard context.hasValidRunID, let store = try? ProofResultStore(runID: context.runID) else {
            if !quiet { message = "Enter the run ID from lisa-verify first." }
            return nil
        }
        return store
    }

    private func append(_ entry: ProofEvidenceEntry) {
        guard let store = store() else { return }
        perform("evidence") { try store.append(entry) }
    }

    private func evidence(caseID: String, check: String, status: ProofStatus, observed: String) -> ProofEvidenceEntry {
        ProofEvidenceEntry(
            runID: context.runID, caseID: caseID, design: nil, check: check, status: status, observed: observed,
            monotonicNanoseconds: ProofMonotonicClock.nowNanoseconds(), wallClock: ProofEvidenceMapping.wallClock())
    }

    private func perform(_ what: String, _ body: () throws -> Void) {
        do {
            try body()
        } catch {
            message = "\(what): \(error)"
        }
    }
}
