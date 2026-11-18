// Test-only. Runs the production extraction service over a host's store with a scripted model in place of the
// configured one, then applies the results through the facade exactly as a maintenance cycle does (review, then change
// propagation). Used by the model-driven integration suites (L09, L10, L19).

import Foundation
import LisaHost
import LisaInference
import LisaReview

/// One review pass with a scripted model.
enum ScriptedReview {
    /// Reviews pending and waiting emails with `provider` and propagates the changes, as `runCycle` does.
    @discardableResult
    static func run(
        _ host: LisaHost, provider: ScriptedModelProvider, limits: ModelUsageLimits = ModelUsageLimits()
    ) async throws -> ReviewReport {
        let services = host.application.services
        let extraction = ExtractionService(
            store: host.storage.records, clock: services.clock, logger: host.logger, settings: services.settings,
            pipeline: ExtractionPipeline(provider: provider, sharing: .localOnly, limits: limits))
        let report = try await extraction.reviewPending()
        try host.application.propagate(report.changes)
        return report
    }
}
