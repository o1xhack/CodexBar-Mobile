import CodexBarCore

extension UsageStore {
    func refreshPathDebugInfo() async {
        let result = await PathBuilder.debugSnapshotAsync(purposes: [.rpc, .tty, .nodeTooling])
        self.pathDebugInfo = result
    }
}
