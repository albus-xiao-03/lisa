// The model configuration on Settings and Health: which model is configured, where it runs, whether it is in use, and
// its daily request limit, as the host reports them without any endpoint address or key.

import Foundation
import LisaPresentation
import SwiftUI

/// The model configuration (UI-01, MODEL-01). Rule-based results are never presented as a language model's.
struct ModelSection: View {
    let settings: SettingsHealthModel

    var body: some View {
        Section("Model") {
            if let model = settings.model {
                LabeledContent("Configured", value: model.title)
                if let location = model.locationText {
                    Text(location)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Label(model.statusMessage, systemImage: model.isAvailable ? "checkmark" : "exclamationmark.triangle")
                    .font(.callout)
                if let limit = model.limitText {
                    Text(limit)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Shown once Lisa's host answers.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
