// One APNs environment's connection state: its fixed endpoint, its HTTP client, its provider-token cache and the gate
// that serializes its requests.

import LisaHTTP

/// Everything one environment needs to send. Provider tokens are cached per connection, because Apple's update
/// limits apply per connection (S11).
final class APNsEnvironmentConnection: Sendable {
    let endpoint: APNsEndpoint
    let client: any HTTPClient
    let tokens: APNsProviderTokenCache
    let gate = APNsRequestGate()

    init(endpoint: APNsEndpoint, client: any HTTPClient, tokens: APNsProviderTokenCache) {
        self.endpoint = endpoint
        self.client = client
        self.tokens = tokens
    }
}
