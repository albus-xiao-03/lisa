// PROOF ONLY — Apps/Proof never ships. Where the owner introduces the three proof devices to each other: name this
// device, generate the shared setup on one device and enter its text on the others, then enter each peer's card
// (typed, pasted, or read from its QR code with the camera app). A peer can be deactivated to model a revocation.

import SwiftUI

struct RosterView: View {
    @Environment(ProofModel.self) private var model
    @State private var setupText = ""
    @State private var cardText = ""
    @State private var showSetup = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section("This device (proof-only)") {
                TextField("Label, for example mac, iphone or ipad", text: $model.label)
                if let card = model.ownCard, let text = try? card.text() {
                    Text(text).font(.caption.monospaced()).textSelection(.enabled)
                    if let image = ProofQRCode.image(for: text) {
                        Image(decorative: image, scale: 1).interpolation(.none).resizable().scaledToFit()
                            .frame(maxWidth: 240)
                    }
                    Text("Operation key: \(model.keys?.operationKeyStorage.rawValue ?? "?")").font(.caption)
                    Text(card.tlsKeySHA256 == nil ? "Design B key: not provisioned" : "Design B key: provisioned")
                        .font(.caption)
                }
                Button("Provision Design B identity") { model.provisionDesignB() }
                ForEach(model.designBSteps.sorted { $0.key < $1.key }, id: \.key) { step in
                    Text("\(step.key): \(step.value)").font(.caption)
                }
            }
            Section("Proof setup (contains the proof discovery secret)") {
                if model.setup == nil {
                    Button("Generate on this device") { model.generateSetup() }
                    TextField("Or enter the setup text from the first device", text: $setupText)
                    Button("Use entered setup") { model.enterSetup(setupText) }
                } else {
                    Toggle("Show setup text to copy to another device", isOn: $showSetup)
                    if showSetup, let text = try? model.setup?.text() {
                        Text(text).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
            Section("Peers") {
                TextField("Enter a peer's lisa-proof-card text", text: $cardText)
                Button("Add peer card") {
                    model.addPeerCard(cardText)
                    cardText = ""
                }
                ForEach(model.peerCards, id: \.deviceID) { card in
                    Toggle(
                        "\(card.label) \(card.deviceID.hex.prefix(8))…",
                        isOn: $model[activeDeviceIDHex: card.deviceID.hex])
                }
            }
        }
    }
}
