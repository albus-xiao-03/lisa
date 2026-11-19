// The App Shortcuts Lisa offers Siri and Spotlight without any setup: one per SIRI-01 action.

import AppIntents
import Foundation

/// Lisa's App Shortcuts (SIRI-01). Every phrase names the app through `\(.applicationName)`; Siri asks for the idea,
/// the text or link, the task or the reminder when a phrase does not say it.
struct LisaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetBriefIntent(),
            phrases: [
                "Get my brief from \(.applicationName)", "Read my \(.applicationName) brief",
                "What's in my \(.applicationName) brief",
            ], shortTitle: "Today's Brief", systemImageName: "newspaper")
        AppShortcut(
            intent: GetRundownIntent(),
            phrases: ["Get my rundown from \(.applicationName)", "What's my plan in \(.applicationName)"],
            shortTitle: "Today's Rundown", systemImageName: "calendar.day.timeline.left")
        AppShortcut(
            intent: CaptureIdeaIntent(),
            phrases: ["Capture an idea in \(.applicationName)", "Save an idea to \(.applicationName)"],
            shortTitle: "Capture Idea", systemImageName: "lightbulb")
        AppShortcut(
            intent: SaveForBriefIntent(),
            phrases: ["Save this for my \(.applicationName) brief", "Save something for \(.applicationName)"],
            shortTitle: "Save for Brief", systemImageName: "tray.and.arrow.down")
        AppShortcut(
            intent: CompleteTaskIntent(),
            phrases: ["Complete a task in \(.applicationName)", "Mark a \(.applicationName) task done"],
            shortTitle: "Complete Task", systemImageName: "checkmark.circle")
        AppShortcut(
            intent: SnoozeReminderIntent(),
            phrases: ["Snooze a reminder in \(.applicationName)", "Snooze my \(.applicationName) reminder"],
            shortTitle: "Snooze Reminder", systemImageName: "zzz")
    }
}
