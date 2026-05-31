import Foundation

@MainActor
extension UsageStore {
    func scheduleMemoryPressureRelief() {
        guard self.memoryPressureReliefTask == nil else { return }

        self.memoryPressureReliefTask = Task.detached(priority: .utility) { [weak self] in
            for delay in [Duration.seconds(2), .seconds(8), .seconds(20)] {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                MemoryPressureRelief.releaseFreeMallocPages()
            }
            await MainActor.run { [weak self] in
                self?.memoryPressureReliefTask = nil
            }
        }
    }
}
