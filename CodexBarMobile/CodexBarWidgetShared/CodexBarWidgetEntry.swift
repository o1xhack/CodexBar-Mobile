import Foundation
import WidgetKit

struct CodexBarWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: CodexBarWidgetConfigurationIntent
    let snapshot: CodexBarWidgetSnapshot
    /// Quota pace widget window choice (Research/071), kept outside the
    /// legacy App Intent so its stored schema does not change.
    var paceWindowChoice: String?
    /// CodexBar widget overview provider selection (Research/073), kept
    /// outside the legacy App Intent for the same reason.
    var overviewSelection: WidgetOverviewSelection = .manual
    /// Overview window and display choices (issue #223), kept outside the
    /// legacy App Intent for the same reason.
    var overviewQuota = WidgetOverviewQuotaOptions()
}
