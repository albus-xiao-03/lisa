// The sheet that stores one `keychain:` secret: typed into a secure field, or read from a key or certificate file
// within the size limit. The value is never shown and is dropped once stored.

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Sets or replaces one Keychain secret (SEC-01). A file's text is stored as it is, without one final line break, as
/// protected files are read; it must be UTF-8 text of at most 64 KiB, such as an APNs `.p8` key or a PEM certificate.
struct KeychainSecretSheet: View {
    let secrets: KeychainSecretsModel
    let entry: KeychainSecretsModel.Entry

    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var fileName: String?
    @State private var isImporting = false
    @State private var problem: String?

    var body: some View {
        Form {
            Section("Secret") {
                LabeledContent("Reference", value: entry.reference.description)
                LabeledContent("Used by", value: entry.settings.joined(separator: ", "))
            }
            Section(
                content: {
                    SecureField("Value", text: $value)
                    HStack {
                        Button("Choose File…") { isImporting = true }
                        if let fileName {
                            Text("Read from \(fileName)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                },
                footer: {
                    Text(
                        "For a key or certificate, choose its file. Lisa keeps the secret in this Mac's Keychain, on "
                            + "this Mac only, and never shows it again."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                })
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 300)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Store") { store() }
                    .disabled(value.isEmpty)
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url): read(url)
            case .failure(let error): problem = "The file couldn't be opened: \(error.localizedDescription)"
            }
        }
    }

    private func store() {
        if secrets.save(value, for: entry.reference) {
            value = ""
            dismiss()
        } else {
            problem = secrets.problem
        }
    }

    /// Reads the chosen file as the secret's value, within the size limit.
    private func read(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= KeychainSecretsModel.maxSecretBytes else {
            problem = "The file is larger than \(KeychainSecretsModel.maxSecretBytes / 1_024) KiB."
            return
        }
        guard let data = try? Data(contentsOf: url), data.count <= KeychainSecretsModel.maxSecretBytes,
            let text = String(data: data, encoding: .utf8), !text.isEmpty
        else {
            problem = "The file isn't UTF-8 text that Lisa can store."
            return
        }
        value = text.hasSuffix("\n") ? String(text.dropLast()) : text
        fileName = url.lastPathComponent
        problem = nil
    }
}
