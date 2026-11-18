// Test-only. Looks up, in a host's store, the notification occurrences of a task's reminders and the per-device
// deliveries made for them, and counts how often a scripted center was asked to present them. Used by the delivery
// and recovery suites (L16, L22, §16.3).

import Foundation
import LisaDomain
import LisaHost

/// A task's reminder notifications and their deliveries.
enum TaskNotifications {
    /// The notification occurrences of `task`'s reminders.
    static func occurrences(of task: TaskID, in host: LisaHost) throws -> [NotificationIntent] {
        let reminders = Set(
            try host.application.all(Reminder.self).filter { $0.subject == .task(task) }.map(\.id))
        return try host.application.all(NotificationIntent.self).filter { intent in
            if case .reminder(let id) = intent.subject { return reminders.contains(id) }
            return false
        }
    }

    /// The device deliveries of those occurrences.
    static func deliveries(of task: TaskID, in host: LisaHost) throws -> [Delivery] {
        let intents = Set(try occurrences(of: task, in: host).map(\.id))
        return try host.application.all(Delivery.self).filter { delivery in
            if case .notification(let id) = delivery.payload { return intents.contains(id) }
            return false
        }
    }

    /// The email copies of `task`'s reminders.
    static func emails(of task: TaskID, in host: LisaHost) throws -> [Delivery] {
        let reminders = Set(
            try host.application.all(Reminder.self).filter { $0.subject == .task(task) }.map(\.id))
        return try host.application.all(Delivery.self).filter { delivery in
            if case .reminder(let id) = delivery.payload { return delivery.channel == .email && reminders.contains(id) }
            return false
        }
    }

    /// How many times `center` was asked to present a notification about `task`.
    static func presentations(of task: TaskID, center: ScriptedNotificationCenter) -> Int {
        center.presented.filter { $0.presentation.subjectID == task.rawValue }.count
    }
}
