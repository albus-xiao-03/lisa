// How Lisa delivers on one channel, from health's delivery modes: live, or a dry run that records and sends nothing.

import Foundation

/// The delivery mode of one channel (UI-01: delivery policy) from health's `deliveryModes`: live, or a dry run in
/// which Lisa records what it would send and sends nothing.
public struct DeliveryChannelMode: Hashable, Sendable, Identifiable {
    /// The host's channel: `email`, `call`, `push` or `localNotification`.
    public var channel: String
    /// The channel in words, such as "Email".
    public var title: String
    /// The host's mode: `live` or `dryRun`.
    public var mode: String
    /// Whether Lisa really delivers on this channel.
    public var isLive: Bool
    /// A sentence about what the mode means.
    public var message: String

    /// The mode `mode` of `channel`.
    public init(channel: String, mode: String) {
        self.channel = channel
        self.mode = mode
        isLive = mode == "live"
        title =
            switch channel {
            case "email": "Email"
            case "call": "Phone calls"
            case "push": "Push notifications"
            case "localNotification": "Notifications on this Mac"
            default: channel
            }
        message =
            switch mode {
            case "live": "Live: Lisa delivers these for real."
            case "dryRun": "Dry run: Lisa records what it would send and sends nothing."
            default: "Mode \"\(mode)\"."
            }
    }

    public var id: String { channel }

    /// The channels of `modes` in a fixed order (email, calls, push, notifications on this Mac), then any others by
    /// name.
    public static func channels(_ modes: [String: String]) -> [DeliveryChannelMode] {
        let order = ["email", "call", "push", "localNotification"]
        let known = order.compactMap { channel in
            modes[channel].map { DeliveryChannelMode(channel: channel, mode: $0) }
        }
        let others = modes.keys.filter { !order.contains($0) }.sorted().map {
            DeliveryChannelMode(channel: $0, mode: modes[$0] ?? "")
        }
        return known + others
    }
}
