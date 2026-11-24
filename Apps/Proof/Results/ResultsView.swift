// PROOF ONLY — Apps/Proof never ships. The run context the owner copies from `lisa-verify pair-session`, the owner's
// local-network prompt observation, the E-2 check, the written records, and the export of `results.jsonl` and
// `evidence.jsonl` for `lisa-verify import-diagnostics` (plan §10.8).

import SwiftUI

struct ResultsView: View {
    @Environment(ProofModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("From lisa-verify pair-session") {
                TextField("Run ID (run-…)", text: $model.context.runID)
                TextField("Case ID (OV-…)", text: $model.context.caseID)
                Picker("Role", selection: $model.context.role) {
                    ForEach(ProofHarnessRole.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                TextField("Devices (mac,iphone …)", text: $model.context.devices)
                TextField("Condition (shared-wifi …)", text: $model.context.condition)
                TextField("Session nonce shown by the harness", text: $model.context.harnessNonce)
                Text("Correlated case ID: \(model.context.correlatedCaseID)").font(.caption.monospaced())
            }
            Section("Local network permission (the owner's observation)") {
                Picker("Prompt", selection: $model.context.permissionPrompt) {
                    Text("not yet observed").tag("")
                    Text("shown").tag("shown")
                    Text("not shown").tag("not-shown")
                }
                Picker("Choice", selection: $model.context.permissionChoice) {
                    Text("not yet observed").tag("")
                    Text("allowed").tag("allowed")
                    Text("denied").tag("denied")
                }
                Button("Record prompt observation") { model.recordPromptObservation() }
            }
            Section("E-2") {
                Button("Run the portable-module check and write its record") { model.runE2() }
            }
            Section("Records (\(model.results.count))") {
                ForEach(Array(model.results.enumerated()), id: \.offset) { _, record in
                    Text("\(record.caseID) \(record.design ?? "") \(record.status.rawValue): \(record.cause)")
                        .font(.caption)
                }
                ForEach(model.exportURLs(), id: \.self) { url in
                    ShareLink(item: url) {
                        Label("Export \(url.lastPathComponent)", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}
