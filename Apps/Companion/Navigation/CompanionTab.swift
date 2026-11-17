// The companion's tabs at compact width: on iPhone, and on iPad in narrow multitasking sizes.

/// A tab of the compact layout. Today holds the rundown and the brief; Settings holds the pending actions,
/// connectivity, connection, notification settings and diagnostics.
enum CompanionTab: Hashable {
    case today
    case capture
    case tasks
    case reminders
    case settings
}
