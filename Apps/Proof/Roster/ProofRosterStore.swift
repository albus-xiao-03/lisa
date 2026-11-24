// PROOF ONLY — Apps/Proof never ships. Keeps what the owner entered for the proof roster: the setup text in the
// Keychain (it holds the discovery secret) and the peers' public cards with their active flags in the app's
// defaults (public keys and synthetic IDs only).

import Foundation

struct ProofRosterStore {
    static let cardsKey = "proof.roster.cards"
    static let inactiveKey = "proof.roster.inactive"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func setup() throws -> ProofSetupText? {
        guard let data = try ProofKeychain.read(ProofSetupText.keychainAccount) else { return nil }
        return try ProofSetupText(text: String(decoding: data, as: UTF8.self))
    }

    /// Stores the setup once; a different setup needs the owner's "reset proof identity" first.
    func saveSetup(_ setup: ProofSetupText) throws {
        try ProofKeychain.add(ProofSetupText.keychainAccount, Data(try setup.text().utf8))
    }

    func peerCards() -> [ProofDeviceCard] {
        (defaults.stringArray(forKey: Self.cardsKey) ?? []).compactMap { try? ProofDeviceCard(text: $0) }
    }

    func addPeerCard(_ card: ProofDeviceCard) throws {
        var texts = defaults.stringArray(forKey: Self.cardsKey) ?? []
        let existing = texts.compactMap { try? ProofDeviceCard(text: $0) }
        // A newer card for the same device (for example once its Design B key exists) replaces the older one.
        texts = zip(texts, existing).filter { $0.1.deviceID != card.deviceID }.map(\.0)
        texts.append(try card.text())
        defaults.set(texts, forKey: Self.cardsKey)
    }

    func inactiveDeviceIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.inactiveKey) ?? [])
    }

    /// Marks a peer inactive or active again: the proof's stand-in for a revocation in a newer roster.
    func setActive(_ active: Bool, deviceIDHex: String) {
        var inactive = inactiveDeviceIDs()
        if active { inactive.remove(deviceIDHex) } else { inactive.insert(deviceIDHex) }
        defaults.set(inactive.sorted(), forKey: Self.inactiveKey)
    }
}
