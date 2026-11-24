// The whole case catalogue (plan §10.8 `Sources/LisaVerifyCases/`): every case by ID, area and session. Later
// milestones add their sessions' cases (X2 at M3, X3 at M5, X4 at M6, X5 and LS-1/LS-2 at M7, X6 and LS-3 at M8,
// X7 at M9).

import LisaVerifyKit

/// Every case the harness knows.
public enum VerifyCatalogue {
    public static var all: [VerifyCase] {
        (X1Catalogue.all + HarnessCatalogue.all).sorted { $0.id < $1.id }
    }

    public static func find(_ id: VerifyCaseID) throws(VerifyError) -> VerifyCase {
        guard let found = all.first(where: { $0.id == id }) else { throw .unknownCase(id.text) }
        return found
    }

    public static func cases(inArea area: String) -> [VerifyCase] {
        all.filter { $0.area == area.uppercased() }
    }

    public static func cases(inSession session: String) -> [VerifyCase] {
        all.filter { $0.session == session.uppercased() }
    }

    /// Fixture cases: what `run --mode fixture` runs on any host without an account.
    public static var fixtureCases: [VerifyCase] {
        all.filter { $0.modes.contains(.fixture) }
    }
}
