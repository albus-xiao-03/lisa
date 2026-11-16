// Device routes of the typed client: pairing, push registration, notification status, preferences and receipts.

import Foundation
import LisaAPIContract

extension LisaAPIClient {
    /// `POST /v1/devices/pairing-codes`: a one-time pairing code. Only the owner on the host may create one.
    public func createPairingCode(requestID: String? = nil) async throws(ClientError) -> PairingCodeDTO {
        try await call(.createPairingCode, requestID: requestID, returning: PairingCodeDTO.self)
    }

    /// `POST /v1/devices/pair`: pairs this installation with a one-time code. The credential the host returns is
    /// stored through the credential store with the device ID and the request's installation ID, and is never returned
    /// to the caller. The request carries no stored credential.
    ///
    /// When the host pairs the device but the credential cannot be stored, this throws
    /// `ClientError.credentialStore`; the device must then pair again with a new code.
    public func pair(_ request: PairDeviceRequest, requestID: String? = nil) async throws(ClientError) -> DeviceDTO {
        let response = try await send(.pairDevice, body: encode(request), requestID: requestID)
        let paired = try ResponseInterpreter.decode(PairDeviceResponse.self, from: response)
        try storeIdentity(
            ClientIdentity(
                installationID: request.installationID, deviceID: paired.device.id, credential: paired.credential))
        return paired.device
    }

    /// `PUT /v1/devices/current/push-registration`: binds this device's APNs token to its registration. Returns the
    /// device.
    public func registerPush(
        _ request: PushRegistrationRequest, requestID: String? = nil
    ) async throws(ClientError) -> DeviceDTO {
        try await call(.pushRegistration, body: encode(request), requestID: requestID, returning: DeviceDTO.self)
    }

    /// `PUT /v1/devices/current/notification-status`: reports this device's notification permission and settings.
    /// Returns the device.
    public func reportNotificationStatus(
        _ request: NotificationStatusRequest, requestID: String? = nil
    ) async throws(ClientError) -> DeviceDTO {
        try await call(.notificationStatus, body: encode(request), requestID: requestID, returning: DeviceDTO.self)
    }

    /// `GET /v1/devices/current/notification-preferences`.
    public func notificationPreferences() async throws(ClientError) -> DeviceNotificationPreferencesDTO {
        try await call(.deviceNotificationPreferences, returning: DeviceNotificationPreferencesDTO.self)
    }

    /// `PATCH /v1/devices/current/notification-preferences`: changes this device's notification preferences at
    /// `request.expectedRevision`. Returns the preferences after the change.
    public func updateNotificationPreferences(
        _ request: DeviceNotificationPreferencesPatch, requestID: String? = nil
    ) async throws(ClientError) -> DeviceNotificationPreferencesDTO {
        try await call(
            .updateDeviceNotificationPreferences, body: encode(request), requestID: requestID,
            returning: DeviceNotificationPreferencesDTO.self)
    }

    /// `POST /v1/devices/current/notification-receipts`: reports notifications this device presented. Any success
    /// body is ignored.
    public func reportReceipts(_ request: NotificationReceiptsRequest, requestID: String? = nil)
        async throws(ClientError)
    {
        _ = try await send(.notificationReceipts, body: encode(request), requestID: requestID)
    }

    /// `GET /v1/devices`: the paired devices.
    public func devices() async throws(ClientError) -> [DeviceDTO] {
        try await call(.listDevices, returning: [DeviceDTO].self)
    }

    /// `DELETE /v1/devices/{id}`: removes a paired device and revokes its credential. Removing this device also clears
    /// its stored pairing. Any success body is ignored.
    public func removeDevice(id: String, requestID: String? = nil) async throws(ClientError) {
        _ = try await send(.removeDevice(id: id), requestID: requestID)
        if let identity = try storedIdentity(), identity.deviceID == id {
            try storeIdentity(identity.unpaired())
        }
    }
}
