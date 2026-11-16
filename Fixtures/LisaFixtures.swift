// Synthetic demonstration resources (DEMO-01) bundled with the package; every item is labeled demonstration content.

import Foundation

/// The bundled demonstration fixtures: `mail/`, `calendar/`, `feeds/` and `demo/` (see `Fixtures/README.md`).
public enum LisaFixtures {
    /// The directory that holds the fixture folders, or `nil` when the resource bundle is missing (for example when
    /// the executable was copied without its `Lisa_LisaFixtures.resources` bundle).
    public static var root: URL? {
        guard let mail = Bundle.module.url(forResource: "mail", withExtension: nil) else { return nil }
        return mail.deletingLastPathComponent()
    }
}
