// The mapping from configuration to the owner settings that policy engines and services read.

import LisaDomain

extension LisaConfiguration {
    /// The owner settings this configuration defines, before stored preferences are overlaid (D-30). Every field of
    /// `OwnerSettings` and of its nested settings comes from the configuration; the approved addresses and number come
    /// only from `delivery`, never from adapters, sources or message content.
    public func ownerSettings() -> OwnerSettings {
        OwnerSettings(
            zone: timeZone,
            planning: planning,
            reminders: reminders,
            calls: CallSettings(
                enabled: delivery.callsEnabled, approvedNumber: delivery.approvedPhoneNumber,
                urgencyWindowMinutes: delivery.calls.urgencyWindowMinutes,
                requireHighPriority: delivery.calls.requireHighPriority,
                requireEarlierUnacknowledgedReminder: delivery.calls.requireEarlierUnacknowledgedReminder,
                maxCallsPerCommitmentPerDay: delivery.calls.maxCallsPerCommitmentPerDay,
                maxCallsPerDay: delivery.calls.maxCallsPerDay),
            delivery: DeliverySettings(
                emailMode: delivery.modes.email, callMode: delivery.modes.call, pushMode: delivery.modes.push,
                emailEnabled: delivery.emailEnabled, approvedEmailAddresses: delivery.approvedEmailAddresses,
                maxAttempts: delivery.maxAttempts, baseBackoffSeconds: delivery.baseBackoffSeconds,
                maxBackoffSeconds: delivery.maxBackoffSeconds, leaseSeconds: delivery.leaseSeconds),
            notifications: NotificationSettings(
                enabled: notifications.enabled,
                timeSensitiveForUrgentDeadlines: notifications.timeSensitiveForUrgentDeadlines,
                urgentDeadlineWindowMinutes: notifications.urgentDeadlineWindowMinutes,
                defaultValidityMinutes: notifications.defaultValidityMinutes,
                notifyBriefAvailability: notifications.notifyBriefAvailability),
            brief: brief,
            dateReading: dateReading,
            newsInterests: news.interests,
            mutedSources: news.mutedSources,
            mutedTopics: news.mutedTopics)
    }
}
