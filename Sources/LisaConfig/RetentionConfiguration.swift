// The `retention` section: how many days raw content, delivery history, audit records and feed items are kept.

/// Retention periods in days (DATA-05, OPS-02); zero keeps a category indefinitely. Logs are bounded by size instead,
/// in `limits`.
public struct RetentionConfiguration: Hashable, Sendable {
    /// Raw source content: message bytes and feed documents.
    public let rawContentDays: Int
    /// Finished deliveries in the outbox.
    public let deliveryHistoryDays: Int
    /// Audit records.
    public let auditDays: Int
    /// Feed items the owner never shared, rated or saved.
    public let feedItemDays: Int

    /// 90 days of raw content, 180 of delivery history, 365 of audit records and 30 of unused feed items.
    public static let defaultValue = RetentionConfiguration(
        rawContentDays: 90, deliveryHistoryDays: 180, auditDays: 365, feedItemDays: 30)

    static func decode(_ section: ConfigSection?) -> RetentionConfiguration {
        let defaults = defaultValue
        guard let section else { return defaults }
        defer { section.finish() }
        return RetentionConfiguration(
            rawContentDays: section.integer("rawContentDays", default: defaults.rawContentDays, in: 0...3650),
            deliveryHistoryDays: section.integer(
                "deliveryHistoryDays", default: defaults.deliveryHistoryDays, in: 0...3650),
            auditDays: section.integer("auditDays", default: defaults.auditDays, in: 0...3650),
            feedItemDays: section.integer("feedItemDays", default: defaults.feedItemDays, in: 0...3650))
    }
}
