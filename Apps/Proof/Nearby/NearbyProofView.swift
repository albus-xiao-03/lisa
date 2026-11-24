// PROOF ONLY — Apps/Proof never ships. The nearby proof's controls (plan §10.5 N-1): design, Design A's suite
// policy, rejoin and selection probe, the injected fault, the frame size, the reconnection trigger the owner is about
// to cause, start and stop, the session code to compare on both screens, and the event log; then "Finish cell".

import SwiftUI

struct NearbyProofView: View {
    @Environment(ProofModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Configuration") {
                Picker("Design", selection: $model.nearbyConfiguration.design) {
                    ForEach(ProofDesign.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                if model.nearbyConfiguration.design == .a {
                    Picker("Suites", selection: $model.nearbyConfiguration.suitePolicy) {
                        ForEach(DesignAPSKSuites.Policy.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Rejoin without discovery secret", isOn: $model.nearbyConfiguration.rejoin)
                    Toggle("Probe listener PSK selection block", isOn: $model.nearbyConfiguration.probeSelectionBlock)
                }
                Picker("Fault", selection: $model.nearbyConfiguration.fault) {
                    ForEach(ProofFaultInjection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Harness role", selection: $model.nearbyConfiguration.harnessRole) {
                    ForEach(ProofHarnessRole.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Stepper(
                    "Frame payload \(model.nearbyConfiguration.framePayloadBytes / 1024) KiB",
                    value: $model.nearbyConfiguration.framePayloadBytes, in: 1_024...1_040_384, step: 64 * 1_024)
                Picker("Next reconnection trigger", selection: $model.nearbyConfiguration.nextReconnectTrigger) {
                    ForEach(ProofReconnectTrigger.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
            Section("Run") {
                if model.nearbyRunning {
                    Button("Stop") { model.stopNearby() }
                    Button("Reconnect now") { model.reconnectNow() }
                } else {
                    Button("Start (foreground only)") { model.startNearby() }
                }
                Text("Session code: \(model.sessionCode ?? "none yet")").font(.title3.monospaced())
                Text("Local network: \(model.localNetworkState?.rawValue ?? "not observed")").font(.caption)
                Button("Finish cell: write the result record") { model.finishCell() }
            }
            Section("Events") {
                ForEach(model.nearbyEvents.reversed()) { event in
                    Text("\(event.monotonicNanoseconds / 1_000_000) ms  \(event.text)").font(.caption.monospaced())
                }
            }
        }
    }
}
