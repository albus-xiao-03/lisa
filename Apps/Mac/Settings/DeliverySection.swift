// Delivery on Settings and Health: each channel's mode, live or a dry run that sends nothing, and the stored
// preferences about who Lisa may contact and how, changed like any preference.

import Foundation
import LisaPresentation
import SwiftUI

/// The delivery policy (UI-01). Channel modes come from the configuration file; the delivery preferences are the
/// owner's stored preferences of the delivery group, shared with the memory screen's model.
struct DeliverySection: View {
    let settings: SettingsHealthModel
    let preferences: MemoryModel
    /// Opens the edit sheet of a preference key.
    let edit: (String) -> Void

    var body: some View {
        Section(
            content: {
                if settings.health.value == nil {
                    Text("Shown once Lisa's host answers.")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.deliveryChannels) { channel in
                    LabeledContent(channel.title) {
                        Label(
                            channel.isLive ? "Live" : "Dry run", systemImage: channel.isLive ? "paperplane" : "doc.text"
                        )
                    }
                    .help(channel.message)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(channel.title): \(channel.message)")
                }
                ForEach(settings.deliveryPreferences, id: \.key) { preference in
                    PreferenceRow(model: preferences, preference: preference, edit: { edit(preference.key) })
                }
                Menu(
                    content: {
                        ForEach(unsetKeys, id: \.key) { descriptor in
                            Button(descriptor.title) { edit(descriptor.key) }
                        }
                    },
                    label: { Text("Set a Delivery Preference") }
                )
                .disabled(unsetKeys.isEmpty)
                .fixedSize()
            },
            header: { Text("Delivery") },
            footer: {
                Text(
                    "A dry run records what Lisa would send and sends nothing. Modes are set in Lisa's configuration "
                        + "file."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            })
    }

    /// The known delivery keys that have no stored preference.
    private var unsetKeys: [PreferenceDescriptor] {
        PreferenceDescriptor.known.filter { $0.group == .delivery && preferences.preference(key: $0.key) == nil }
    }
}
