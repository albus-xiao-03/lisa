// The certificate screen of the connection settings (API-01, NOTIFY-07): trust the owner's certificate, or the
// certificate authority that issued it, for the Lisa host, optionally with a pin of the host's own certificate.

import LisaPresentation
import SwiftUI
import UniformTypeIdentifiers

/// The TLS trust for the Lisa host. With the owner's certificate, the app trusts only it for the host
/// (`PinnedServerTrustEvaluator`); otherwise this device's trusted certificate authorities decide. Certificate checks
/// are never turned off, and a certificate that can't be used changes nothing.
struct HostTrustView: View {
    let controller: HostConnectionController
    @State private var trust: HostTrustSettings?
    @State private var loadProblem: String?
    @State private var pinText = ""
    @State private var isChoosingFile = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("Trusted Now") {
                if let trust {
                    Label(trustText(trust), systemImage: "lock.shield")
                    if trust.leafCertificateSHA256 != nil {
                        Label("Your host's own certificate is pinned too.", systemImage: "pin")
                    }
                } else {
                    Label("This device's trusted certificate authorities.", systemImage: "lock")
                }
            }
            Section(
                content: {
                    TextField("SHA-256 pin (optional)", text: $pinText)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Choose Certificate File…", systemImage: "doc.badge.plus") {
                        isChoosingFile = true
                    }
                },
                header: { Text("Your Host's Certificate") },
                footer: {
                    Text(
                        "Choose your Lisa host's certificate, or the certificate authority that issued it, as a PEM or "
                            + "DER file. To pin the host's own certificate as well, enter its SHA-256 fingerprint "
                            + "before choosing the file.")
                })
            if trust != nil {
                Section {
                    Button(
                        role: .destructive, action: useSystemTrust,
                        label: { Label("Use This Device's Trusted Authorities", systemImage: "arrow.uturn.backward") })
                }
            }
            if let message {
                Section {
                    Text(message)
                }
            }
            if let loadProblem {
                Section {
                    Label(loadProblem, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Certificate")
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.x509Certificate, .data]) { result in
            useCertificate(from: result)
        }
        .onAppear(perform: showCurrent)
    }

    private func trustText(_ trust: HostTrustSettings) -> String {
        let count = trust.anchorCertificates.count
        return count == 1 ? "Your certificate, and nothing else." : "Your \(count) certificates, and nothing else."
    }

    private func useCertificate(from result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            let file = try CertificateFileReader.read(url)
            let chosen = try HostTrustSettings(certificateFile: file, leafPin: pinText)
            try controller.setTrust(chosen)
            message = "Lisa now trusts only this certificate for your host."
        } catch {
            message = "That certificate can't be used: \(error)."
        }
        showCurrent()
    }

    private func useSystemTrust() {
        do {
            try controller.setTrust(nil)
            message = "This device's trusted certificate authorities decide again."
        } catch {
            message = "The setting couldn't be changed: \(error)."
        }
        showCurrent()
    }

    /// Reads the controller again; it is not observable, so the screen keeps its own copy.
    private func showCurrent() {
        trust = controller.trust
        loadProblem = controller.loadProblem
    }
}
