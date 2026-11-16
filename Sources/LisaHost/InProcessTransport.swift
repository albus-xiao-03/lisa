// The in-process API transport and the runtime-status bridge used by the router.

import Foundation
import LisaAPI
import LisaAPIContract
import LisaRuntime

/// Sends requests straight to the router inside the host process. The owner transport acts as the local owner; the
/// device transport authenticates each request by its device credential, exactly like the network server.
public struct InProcessTransport: APITransport {
    let router: APIRouter
    let origin: RequestOrigin

    public init(router: APIRouter, origin: RequestOrigin) {
        self.router = router
        self.origin = origin
    }

    public func send(_ request: APIRequest) async throws -> APIResponse {
        await router.handle(request, origin: origin)
    }
}

/// Reports the runtime's health facts to the router.
struct RuntimeStatusBridge: RuntimeStatusProvider {
    let runtime: HostRuntime

    func runtimeStatus() -> RuntimeStatus {
        let health = runtime.health()
        return RuntimeStatus(
            startedAt: health.startedAt, lastCycleAt: health.lastCycleAt, lastCycleProblem: health.lastCycleProblem,
            warnings: health.warnings)
    }
}
