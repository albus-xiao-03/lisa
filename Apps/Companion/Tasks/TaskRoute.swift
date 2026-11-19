// The value that opens one task's detail from the tasks list.

/// A task to show in detail, by the host's stable task identifier.
struct TaskRoute: Hashable {
    let taskID: String
}
