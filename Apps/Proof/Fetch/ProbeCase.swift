// PROOF ONLY — Apps/Proof never ships. The E-1 probe cases, `OV-APPLE-X1-FETCH-01`–`09` (plan §10.9 E-1 row), in
// the order §8.9.3 "Feasibility first" lists them. §10.5/§10.6 also require IP literals and redirects to them at X1;
// §10.9 gives them no IDs of their own, so they are subcases of the nearest case (docs/DECISIONS.md D-54). Every
// URL and name is the owner's: an owner-authorized public URL or a controlled endpoint the owner runs.

struct ProbeSubcase: Sendable, Identifiable {
    let id: String
    let label: String
    /// A suggested value the owner may replace (fixed literals from plan §8.9.3 S-14); empty means owner-supplied.
    let suggestion: String
    /// The trace's `finalOutcome` values that pass.
    let passingOutcomes: Set<String>
}

struct ProbeCase: Sendable, Identifiable {
    let id: String
    let title: String
    let subcases: [ProbeSubcase]
    /// What only the owner can observe (the network listener, the proxy's log), recorded beside the trace.
    let ownerObservation: String?
    /// Network setup the owner arranges first.
    let setup: String

    static let all: [ProbeCase] = [
        ProbeCase(
            id: "OV-APPLE-X1-FETCH-01", title: "Owner-authorized public URL over https",
            subcases: [
                .init(id: "public-url", label: "Public https URL", suggestion: "", passingOutcomes: ["fetched"]),
                .init(
                    id: "public-ipv4-literal", label: "Public IPv4-literal https URL (certificate with an IP SAN)",
                    suggestion: "", passingOutcomes: ["fetched"]),
            ], ownerObservation: nil, setup: "Any network with Internet; Core not configured"),
        ProbeCase(
            id: "OV-APPLE-X1-FETCH-02", title: "Private destinations refused before any TCP connection",
            subcases: [
                .init(
                    id: "private-only-name", label: "Name resolving only to a private address", suggestion: "",
                    passingOutcomes: ["refused-before-connect"]),
                .init(
                    id: "private-ipv4-literal", label: "Private IPv4 literal", suggestion: "https://10.0.0.5/",
                    passingOutcomes: ["refused-before-connect"]),
                .init(
                    id: "mapped-private-literal", label: "IPv4-mapped private literal",
                    suggestion: "https://[::ffff:10.0.0.5]/", passingOutcomes: ["refused-before-connect"]),
                .init(
                    id: "well-known-prefix-private-literal", label: "64:ff9b:: literal of a private address",
                    suggestion: "https://[64:ff9b::a00:5]/", passingOutcomes: ["refused-before-connect"]),
                .init(
                    id: "redirect-to-private", label: "Public URL redirecting to a private address",
                    suggestion: "", passingOutcomes: ["redirect-stopped-refused"]),
            ], ownerObservation: "The listener on the owner's network recorded no connection from this device",
            setup: "Controlled DNS names and a listener on the owner's network"),
        ProbeCase(
            id: "OV-APPLE-X1-FETCH-03", title: "Mixed name dialed only at its public address",
            subcases: [
                .init(
                    id: "mixed-name", label: "Name with one public and one private A record", suggestion: "",
                    passingOutcomes: ["fetched"])
            ], ownerObservation: "The listener at the private address recorded no connection",
            setup: "Controlled DNS name with mixed A records"),
        ProbeCase(
            id: "OV-APPLE-X1-FETCH-04", title: "A configured system proxy is not used",
            subcases: [
                .init(
                    id: "public-url-with-proxy", label: "Public URL with a system proxy configured", suggestion: "",
                    passingOutcomes: ["fetched"])
            ], ownerObservation: "The proxy's log shows no request from this device",
            setup: "System HTTP/HTTPS proxy configured on this device"),
        ProbeCase(
            id: "OV-APPLE-X1-FETCH-05", title: "IPv6-only NAT64 network (macOS Internet Sharing)",
            subcases: [
                .init(
                    id: "public-url-nat64", label: "Public URL (dialed at its synthesized address)",
                    suggestion: "", passingOutcomes: ["fetched"]),
                .init(
                    id: "translated-public-literal", label: "64:ff9b:: literal of a public address",
                    suggestion: "", passingOutcomes: ["fetched"]),
            ], ownerObservation: nil, setup: "IPv6-only Wi-Fi from macOS Internet Sharing with NAT64"),
        ProbeCase(
            id: "OV-APPLE-X1-FETCH-06", title: "Dual-stack network: A records only; unverifiable IPv6 deferred",
            subcases: [
                .init(
                    id: "public-url-dual-stack", label: "Public URL (dialed over IPv4)", suggestion: "",
                    passingOutcomes: ["fetched"]),
                .init(
                    id: "aaaa-only-name", label: "AAAA-only name", suggestion: "",
                    passingOutcomes: ["deferred-to-core"]),
                .init(
                    id: "global-ipv6-literal", label: "Global IPv6-literal URL", suggestion: "",
                    passingOutcomes: ["deferred-to-core"]),
                .init(
                    id: "redirect-to-global-ipv6-literal", label: "Redirect to a global IPv6 literal",
                    suggestion: "", passingOutcomes: ["redirect-stopped-deferred"]),
            ], ownerObservation: nil, setup: "Dual-stack network"),
        ProbeCase(
            id: "OV-APPLE-X1-FETCH-07", title: "Independently translated destination never dialed by its AAAA",
            subcases: [
                .init(
                    id: "translated-only-name", label: "Test name with a synthesized AAAA only", suggestion: "",
                    passingOutcomes: ["deferred-to-core"])
            ], ownerObservation: "The owner's listener behind the translator recorded no connection",
            setup: "The owner's controlled resolver synthesizing AAAA for the test name only; ipv4only.arpa negative"),
        ProbeCase(
            id: "OV-APPLE-X1-FETCH-08", title: "Split-tunnel VPN: one interface or fail closed",
            subcases: [
                .init(
                    id: "public-url-split-vpn", label: "Public URL with the owner's split-tunnel VPN up",
                    suggestion: "", passingOutcomes: ["fetched", "failed-closed"])
            ], ownerObservation: nil, setup: "The owner's split-tunnel VPN connected"),
        ProbeCase(
            id: "OV-APPLE-X1-FETCH-09", title: "Platform behavior the design relies on",
            subcases: [
                .init(
                    id: "platform-facts", label: "Public name with A records", suggestion: "",
                    passingOutcomes: ["recorded"])
            ], ownerObservation: "In Xcode's SDK: grep for nw_nat64_copy_prefixes_async in Network.framework headers",
            setup: "Any network with Internet"),
    ]
}
