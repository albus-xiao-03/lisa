// The three device pairs and three network conditions of the nearby cells (plan §8.7, §10.5 N-1, §10.9 R2-A03/A04).

/// A device pair of a nearby cell.
public enum NearbyPair: String, Sendable, CaseIterable {
    /// Mac–iPhone.
    case macIPhone = "MI"
    /// Mac–iPad.
    case macIPad = "MP"
    /// iPhone–iPad.
    case iPhoneIPad = "IP"

    /// The `--devices` value of `lisa-verify pair-session`.
    public var devices: String {
        switch self {
        case .macIPhone: "mac,iphone"
        case .macIPad: "mac,ipad"
        case .iPhoneIPad: "iphone,ipad"
        }
    }

    public var title: String {
        switch self {
        case .macIPhone: "Mac–iPhone"
        case .macIPad: "Mac–iPad"
        case .iPhoneIPad: "iPhone–iPad"
        }
    }
}

/// A network condition of a nearby cell; its case number is the cell's `NN`.
public enum NearbyCondition: String, Sendable, CaseIterable {
    case sharedWiFi = "shared-wifi"
    case noInternet = "no-internet"
    case noAccessPoint = "no-access-point"

    public var number: String {
        switch self {
        case .sharedWiFi: "01"
        case .noInternet: "02"
        case .noAccessPoint: "03"
        }
    }

    public var setup: String {
        switch self {
        case .sharedWiFi: "Both devices joined to the same Wi-Fi network, with Internet access"
        case .noInternet: "Both devices on the same Wi-Fi network with the router's Internet connection unplugged"
        case .noAccessPoint:
            "Wi-Fi on but joined to no network on both devices (forget or leave the network), so only peer-to-peer "
                + "Wi-Fi remains; Bluetooth on"
        }
    }
}
