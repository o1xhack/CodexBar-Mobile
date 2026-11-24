import CodexBarCore

extension UsageStore {
    func refreshPathDebugInfo(
        load: @MainActor () async -> PathDebugSnapshot = {
            await withCheckedContinuation { continuation in
                LoginShellPathCache.shared.captureOnce { _ in continuation.resume() }
            }
            return await PathBuilder.debugSnapshotAsync(purposes: [.rpc, .tty, .nodeTooling])
        }) async
    {
        self.pathDebugInfo = await load()
    }
}
