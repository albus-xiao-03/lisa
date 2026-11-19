// The source of effective owner settings: configuration defaults overlaid with confirmed preferences.

import LisaDomain

/// Supplies the settings in effect now.
public protocol SettingsSource: Sendable {
    func currentSettings() throws -> OwnerSettings
}
