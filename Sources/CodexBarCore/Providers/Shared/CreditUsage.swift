/// Reconciles optional credit counters without changing provider-specific display policy.
struct CreditUsage {
    let total: Double?
    let used: Double

    init(used: Double?, total: Double?, remaining: Double?) {
        if let total {
            self.total = max(0, total)
        } else if let used, let remaining {
            self.total = max(0, used + remaining)
        } else {
            self.total = nil
        }
        if let used {
            self.used = max(0, used)
        } else if let total = self.total, let remaining {
            self.used = max(0, total - remaining)
        } else {
            self.used = 0
        }
    }
}
