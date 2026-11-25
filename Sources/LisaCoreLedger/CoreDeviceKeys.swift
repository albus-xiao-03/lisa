// A device's operation-key rotation at Core (plan §8.1.4 "device key rotation"): the authenticated device presents an
// update signed by its current and its next key; in one write transaction Core checks both signatures, that the
// previous key is the registry's, that the next key is new, and that none of the device's operations wait for
// dependencies (they would commit after the change under the old key). It then keeps the previous key in the device's
// history, makes the next key current, and signs a new roster that lists the previous key, so the device's committed
// operations still verify while new ones verify only with the next key.

import Foundation
import LisaCrypto
import LisaSQLite
import LisaSyncProtocol
import LisaTrust

/// Why Core refused a device key update.
public enum CoreKeyUpdateRefusal: Hashable, Sendable {
    case malformed
    /// Not signed by both keys, for another device or dataset, or from a key the registry doesn't hold for it.
    case invalid
    case revokedDevice
    /// The next key is, or was, some device's key.
    case keyInUse
    /// Operations of the device wait for dependencies at Core; rotate once they are decided.
    case operationsWaiting

    public var code: String {
        switch self {
        case .malformed: "invalid_request"
        case .invalid: "key_update_invalid"
        case .revokedDevice: "device_revoked"
        case .keyInUse: "key_update_key_in_use"
        case .operationsWaiting: "key_update_operations_waiting"
        }
    }

    public var status: Int {
        switch self {
        case .malformed: 400
        case .invalid, .revokedDevice: 403
        case .keyInUse, .operationsWaiting: 409
        }
    }
}

/// What Core answered a device key update.
public enum CoreKeyUpdateAnswer: Hashable, Sendable {
    /// The new roster, naming the next key and keeping the previous one in the device's history.
    case updated(SignedRoster)
    case refused(CoreKeyUpdateRefusal)
}

extension CoreTrust {
    /// Rotates the authenticated `device`'s operation key (`POST /v2/devices/current/key-update`).
    public func updateDeviceKey(_ device: Identifier128, wireBody: [UInt8]) throws(CoreLedgerError)
        -> CoreKeyUpdateAnswer
    {
        let signed: SignedKeyTransition
        do {
            signed = try DeviceKeyUpdate.request(fromBody: wireBody)
        } catch {
            return .refused(.malformed)
        }
        guard let (update, _) = try? DeviceKeyUpdateSigning.verify(signed), update.deviceID == device,
            update.datasetID == ledger.datasetID
        else { return .refused(.invalid) }
        let time = now()
        return try ledger.write { session, _ in
            guard
                let row = try session.query(
                    "SELECT status, operation_key FROM core_devices WHERE device_id = ?", [CoreColumns.id(device)]
                ).first
            else { return .refused(.invalid) }
            guard case .text("active") = row[0] else { return .refused(.revokedDevice) }
            guard try CoreColumns.bytes(row[1]) == update.previousKey else { return .refused(.invalid) }
            let next = CoreColumns.bytes(update.nextKey)
            guard
                try session.query("SELECT 1 FROM core_devices WHERE operation_key = ?", [next]).isEmpty,
                try session.query("SELECT 1 FROM core_device_keys WHERE operation_key = ?", [next]).isEmpty
            else { return .refused(.keyInUse) }
            guard
                try session.query(
                    "SELECT 1 FROM core_operations WHERE origin_device = ? AND state = 'waiting' LIMIT 1",
                    [CoreColumns.id(device)]
                ).isEmpty
            else { return .refused(.operationsWaiting) }
            let sequence =
                (try session.query(
                    "SELECT max(sequence) FROM core_device_keys WHERE device_id = ?", [CoreColumns.id(device)]
                ).first?.first?.integer ?? 0) + 1
            let head =
                try session.query("SELECT last_position FROM core_dataset WHERE singleton = 1").first?.first?
                .integer ?? 0
            try session.query(
                """
                INSERT INTO core_device_keys (device_id, sequence, operation_key, retired_at_position, update_body,
                  previous_signature, next_signature, recorded_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    CoreColumns.id(device), .integer(sequence), CoreColumns.bytes(update.previousKey),
                    .integer(head + 1),
                    CoreColumns.bytes(signed.body), CoreColumns.bytes(signed.previousSignature),
                    CoreColumns.bytes(signed.nextSignature), .integer(time),
                ])
            try session.query(
                "UPDATE core_devices SET operation_key = ? WHERE device_id = ?", [next, CoreColumns.id(device)])
            try Self.recordEvent(
                "device_key_rotated", subject: device, detail: "key \(sequence) retired at position \(head + 1)", time,
                session)
            return .updated(try self.signRoster(in: session, time: time).signed)
        }
    }

    /// A device's previous operation keys, oldest first.
    static func previousKeys(of device: Identifier128, in session: SQLiteSession) throws -> [[UInt8]] {
        try session.query(
            "SELECT operation_key FROM core_device_keys WHERE device_id = ? ORDER BY sequence", [CoreColumns.id(device)]
        ).map { try CoreColumns.bytes($0[0]) }
    }
}
