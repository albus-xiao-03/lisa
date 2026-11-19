// The host's names for notification categories, as this device's preferences list them.

import Foundation
import LisaAPIContract

/// The host's category names (`reminder`, `overdue`, ...) for the categories the apps register.
enum NotificationCategoryNames {
    /// The host's name of `category`, as `DeviceNotificationPreferencesDTO.categories` lists it.
    static func name(of category: NotificationCategoryID) -> String {
        switch category {
        case .reminder: "reminder"
        case .overdue: "overdue"
        case .planBlock: "planBlock"
        case .eventProposal: "eventProposal"
        case .commitmentChange: "commitmentChange"
        case .brief: "brief"
        }
    }
}
