// The owner's configuration as the Mac app reads it: the file the `lisa` commands read ($LISA_CONFIG, then
// ~/.config/lisa/config.json5), validated, and the host settings it gives (D-50).

import Foundation
import LisaConfig
import LisaHost

/// The configuration that the embedded host and the client fallback use (D-50: the app, `lisa serve` and the CLI share
/// one configuration and one data directory under one lock).
///
/// The app has no `--config` or `--data-dir` options. It reads `$LISA_CONFIG` when the environment the app was started
/// in sets it, and otherwise `~/.config/lisa/config.json5`, as `HostSession` does without options. The data directory
/// is the configured one.
struct MacHostConfiguration: Sendable {
    /// Why the configuration cannot be used. The message names the file and the settings, never a secret value.
    struct Problem: Error, CustomStringConvertible {
        let description: String
    }

    /// The file that was read.
    let path: String
    /// The validated configuration.
    let configuration: LisaConfiguration
    /// The host settings it gives.
    let settings: HostSettings

    /// The configuration file the app reads.
    static var resolvedPath: String {
        if let environment = ProcessInfo.processInfo.environment["LISA_CONFIG"], !environment.isEmpty {
            return (environment as NSString).expandingTildeInPath
        }
        return ("~/.config/lisa/config.json5" as NSString).expandingTildeInPath
    }

    /// The version the host reports in health, backups and exports: this build's version and build number.
    static var applicationVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else { return "\(version) (Mac)" }
        return "\(version) (Mac, build \(build))"
    }

    /// Reads and validates the configuration file and builds the host settings, or says why it cannot.
    static func load() throws(Problem) -> MacHostConfiguration {
        let path = resolvedPath
        let configuration: LisaConfiguration
        do throws(ConfigurationError) {
            configuration = try ConfigurationLoader.load(path: path)
        } catch {
            throw Problem(description: error.description)
        }
        let settings: HostSettings
        do {
            settings = try HostSettings(configuration: configuration, applicationVersion: applicationVersion)
        } catch {
            throw Problem(description: "the configuration \(path) can't be used: \(error)")
        }
        return MacHostConfiguration(path: path, configuration: configuration, settings: settings)
    }
}
