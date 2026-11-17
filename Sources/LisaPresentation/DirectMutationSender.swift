// Sending a mutation once without the offline queue, for the rare case that the queue cannot take it.

import Foundation
import LisaAPIContract
import LisaClient

/// Sends a mutation once, with a new request ID, through the typed client. Used only when the offline queue refuses an
/// action (full, or its storage failed), so the action is still tried while the host can be reached.
enum DirectMutationSender {
    /// Sends `mutation` and returns the host's success response as JSON (empty for receipts).
    static func send(_ mutation: QueuedMutation, using client: LisaAPIClient) async throws(ClientError) -> Data {
        switch mutation {
        case .capture(let request):
            return try encode(try await client.capture(request))
        case .updateTask(let id, let request):
            return try encode(try await client.updateTask(id: id, request))
        case .reminderAction(let id, let request):
            return try encode(try await client.reminderAction(id: id, request))
        case .notificationAction(let id, let request):
            return try encode(try await client.notificationAction(id: id, request))
        case .proposalAction(let id, let request):
            return try encode(try await client.proposalAction(id: id, request))
        case .planBlockAction(let planID, let blockID, let request):
            return try encode(try await client.planBlockAction(planID: planID, blockID: blockID, request))
        case .updatePreferences(let request):
            return try encode(try await client.updatePreferences(request))
        case .updateNotificationPreferences(let request):
            return try encode(try await client.updateNotificationPreferences(request))
        case .notificationReceipts(let request):
            try await client.reportReceipts(request)
            return Data()
        }
    }

    private static func encode<Value: Encodable>(_ value: Value) throws(ClientError) -> Data {
        do {
            return try APIJSON.encoder().encode(value)
        } catch {
            throw .encoding("\(Value.self) could not be encoded as JSON")
        }
    }
}
