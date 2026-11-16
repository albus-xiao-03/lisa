// `lisa doctor`: validates the configuration and reports capabilities without sending anything (CLI-01, CFG-02).

import ArgumentParser
import Foundation
import LisaConfig
import LisaHost
import LisaRuntime
import LisaSecrets

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Validate the configuration and report capabilities without sending messages.",
        discussion: "Secrets are resolved to check access only; their values are never printed.")

    @OptionGroup var host: HostOptions

    struct Check: Encodable {
        var name: String
        var ok: Bool
        var detail: String
    }

    func run() async throws {
        let configuration = try HostSession.configuration(host)
        let settings = try HostSession.settings(configuration, host)
        var checks = [
            Check(
                name: "configuration", ok: true,
                detail: "\(host.resolvedConfigPath) is valid (version \(configuration.version))")
        ]
        do {
            let lock = try DataDirectoryLock.acquire(directory: settings.dataDirectory, mode: "doctor", now: Date())
            lock.release()
            checks.append(
                Check(
                    name: "data directory", ok: true,
                    detail: "\(settings.dataDirectory.path) is writable and not in use"))
        } catch {
            checks.append(Check(name: "data directory", ok: false, detail: String(describing: error)))
        }
        let modes = configuration.delivery.modes
        checks.append(
            Check(
                name: "delivery", ok: !configuration.hasLiveDelivery,
                detail: "email \(modes.email.rawValue), calls \(modes.call.rawValue), push \(modes.push.rawValue)"
                    + (configuration.hasLiveDelivery
                        ? "; live delivery is configured, but this build has no live delivery adapter, so the host would refuse to start"
                        : "; nothing is sent until a channel is set to live")))
        for source in settings.sources {
            switch source.access {
            case .localDirectory(let url, _), .localFile(let url, _):
                let exists = FileManager.default.fileExists(atPath: url.path)
                checks.append(
                    Check(
                        name: "source \(source.key)", ok: exists,
                        detail: exists ? "local files at \(url.path)" : "\(url.path) does not exist"))
            case .adapter(let description):
                checks.append(
                    Check(
                        name: "source \(source.key)", ok: false,
                        detail:
                            "the \(description) adapter is not in this build; the source will be reported unavailable"))
            }
        }
        if case .openAICompatible = settings.model {
            checks.append(
                Check(
                    name: "model", ok: false,
                    detail: "the OpenAI-compatible adapter is not in this build; email waits for a model"))
        } else {
            checks.append(
                Check(
                    name: "model", ok: true,
                    detail:
                        "provider \(configuration.model.provider.rawValue), data sharing \(configuration.model.dataSharing.rawValue)"
                ))
        }
        let secrets = CompositeSecretStore()
        for secret in configuration.referencedSecrets {
            do {
                _ = try secrets.secret(for: secret.reference)
                checks.append(Check(name: "secret \(secret.path)", ok: true, detail: "\(secret.reference) resolves"))
            } catch {
                checks.append(
                    Check(
                        name: "secret \(secret.path)", ok: false,
                        detail: "\(secret.reference) does not resolve: \(error)"))
            }
        }
        checks.append(
            Check(
                name: "api", ok: true,
                detail:
                    "bind \(configuration.api.bindAddress):\(configuration.api.port), TLS \(configuration.api.tls.mode.rawValue)"
                    + " (the network server is not in this build)"))
        try host.output.emit(checks) { checks in
            checks.map { "[\($0.ok ? "ok" : "!!")] \($0.name): \($0.detail)" }.joined(separator: "\n")
        }
        if checks.contains(where: { !$0.ok }) { throw LisaExit.checksFailed }
    }
}
