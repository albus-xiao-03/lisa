// Owner-verification UI tests (plan R2 §10.8 `Apps/OwnerVerification/`), the automated part of harness test plan X1:
// they drive the actual Lisa Proof app (scheme LisaProof) on the destination the owner picks. Everything N-1 and E-1
// need beyond this — two devices, radios, network conditions, faults, the permission prompt — is guided by
// `lisa-verify guide <case>` and recorded through the app's own result export.

import XCTest

final class ProofSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The proof app launches under its proof-only banner and shows its four areas and the run context fields.
    @MainActor
    func testProofLaunchesWithBannerAreasAndRunContext() throws {
        let app = XCUIApplication()
        app.launch()
        let banner = app.staticTexts["PROOF ONLY — synthetic identities, never a production app"]
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "the proof-only banner is missing")
        for area in ["Roster", "Nearby", "Fetch", "Results"] {
            XCTAssertTrue(
                app.descendants(matching: .any)[area].firstMatch.waitForExistence(timeout: 5),
                "the \(area) area is missing")
        }
        app.descendants(matching: .any)["Results"].firstMatch.tap()
        XCTAssertTrue(
            app.textFields["Run ID (run-…)"].waitForExistence(timeout: 5), "the run context fields are missing")
        XCTAssertTrue(app.textFields["Session nonce shown by the harness"].exists)
    }
}
