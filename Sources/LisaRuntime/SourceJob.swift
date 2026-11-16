// A source synchronization job: a connector with its batch processor, run by the connector runner.

import Foundation
import LisaDomain
import LisaIngestion
import LisaPorts

/// One configured source with how to synchronize it. Each job is isolated: its failure never stops other jobs.
public struct SourceJob: Sendable {
    /// The source's configuration key; also the job's schedule key.
    public let key: String
    public let sourceID: SourceID
    /// Time between successful synchronizations.
    public let interval: TimeInterval
    let synchronize: @Sendable (ConnectorRunner) async -> SyncReport

    public init<Processor: BatchProcessor>(
        key: String, sourceID: SourceID, interval: TimeInterval, connector: any SourceConnector, processor: Processor,
        limits: SyncLimits, maxPages: Int = 10
    ) {
        self.key = key
        self.sourceID = sourceID
        self.interval = max(60, interval)
        self.synchronize = { runner in
            await runner.synchronize(
                sourceID: sourceID, connector: connector, processor: processor, limits: limits, maxPages: maxPages)
        }
    }
}
