import Foundation

package enum CodexDisplacedLivePreservationNoneReason: Equatable {
    case liveMissing
    case targetMatchesLiveAuthIdentity
}

package enum CodexDisplacedLivePreservationRejectReason: Equatable {
    case liveUnreadable
    case liveAPIKeyOnlyUnsupported
    case liveIdentityMissingForPreservation
    case conflictingReadableManagedHome
}

package enum CodexDisplacedLivePreservationImportReason: Equatable {
    case noExistingManagedDestination
}

package enum CodexDisplacedLivePreservationRefreshReason: Equatable {
    case readableHomeIdentityMatch
    case readableHomeIdentityMatchUsingPersistedEmailFallback
}

package enum CodexDisplacedLivePreservationRepairReason: Equatable {
    case persistedProviderMatchWithMissingHome
    case persistedProviderMatchWithUnreadableHome
    case persistedLegacyEmailMatch
}

package enum CodexDisplacedLivePreservationPlan {
    case none(reason: CodexDisplacedLivePreservationNoneReason)
    case reject(reason: CodexDisplacedLivePreservationRejectReason)
    case importNew(reason: CodexDisplacedLivePreservationImportReason)
    case refreshExisting(
        destination: PreparedStoredManagedAccount,
        reason: CodexDisplacedLivePreservationRefreshReason)
    case repairExisting(
        destination: PreparedStoredManagedAccount,
        reason: CodexDisplacedLivePreservationRepairReason)
}

package struct CodexDisplacedLivePreservationPlanner {
    package func makePlan(context: PreparedPromotionContext) -> CodexDisplacedLivePreservationPlan {
        switch context.live.homeState {
        case .missing:
            return .none(reason: .liveMissing)
        case .unreadable:
            return .reject(reason: .liveUnreadable)
        case .apiKeyOnly:
            return .reject(reason: .liveAPIKeyOnlyUnsupported)
        case .readable:
            break
        }

        guard let liveAuthIdentity = context.live.authIdentity else {
            return .reject(reason: .liveIdentityMissingForPreservation)
        }

        let targetIdentity = context.target.remoteIdentity
        if CodexIdentityMatcher.matches(
            targetIdentity.identity,
            lhsEmail: targetIdentity.email,
            liveAuthIdentity.identity,
            rhsEmail: liveAuthIdentity.email)
        {
            return .none(reason: .targetMatchesLiveAuthIdentity)
        }

        let candidates = context.storedManagedAccounts.filter { $0.persisted.id != context.target.persisted.id }
        if let destination = self.findReadableHomeMatch(in: candidates, liveAuthIdentity: liveAuthIdentity) {
            let reason: CodexDisplacedLivePreservationRefreshReason =
                if liveAuthIdentity.email == nil {
                    .readableHomeIdentityMatchUsingPersistedEmailFallback
                } else {
                    .readableHomeIdentityMatch
                }
            return .refreshExisting(destination: destination, reason: reason)
        }

        let repairCandidates = candidates.filter { candidate in
            let persisted = candidate.persisted
            if case let .providerAccount(id) = liveAuthIdentity.identity,
               persisted.effectiveWorkspaceAccountID == ManagedCodexAccount.normalizeWorkspaceAccountID(id)
            {
                return liveAuthIdentity.email == nil || persisted.email == liveAuthIdentity.email
            }
            return liveAuthIdentity.identity != .unresolved && persisted.effectiveWorkspaceAccountID == nil &&
                persisted.email == liveAuthIdentity.email
        }
        let providerCandidates = repairCandidates.filter { $0.persisted.effectiveWorkspaceAccountID != nil }
        let destinations = providerCandidates.isEmpty ? repairCandidates : providerCandidates
        if self.hasConflictingReadableHome(in: destinations, liveAuthIdentity: liveAuthIdentity) {
            return .reject(reason: .conflictingReadableManagedHome)
        }

        if let repaired = self.findPersistedRepairMatch(in: destinations) {
            return .repairExisting(destination: repaired.destination, reason: repaired.reason)
        }

        guard liveAuthIdentity.identity != .unresolved, liveAuthIdentity.email != nil else {
            return .reject(reason: .liveIdentityMissingForPreservation)
        }

        return .importNew(reason: .noExistingManagedDestination)
    }

    private func findReadableHomeMatch(
        in candidates: [PreparedStoredManagedAccount],
        liveAuthIdentity: PreparedIdentity)
        -> PreparedStoredManagedAccount?
    {
        candidates.first { candidate in
            guard let candidateAuthIdentity = candidate.authIdentity else { return false }
            let candidateRemoteIdentity = candidate.remoteIdentity
            return CodexIdentityMatcher.matches(
                candidateRemoteIdentity.identity,
                lhsEmail: candidateRemoteIdentity.email,
                liveAuthIdentity.identity,
                rhsEmail: liveAuthIdentity.email) &&
                CodexIdentityMatcher.matches(
                    candidateAuthIdentity.identity,
                    lhsEmail: candidateAuthIdentity.email,
                    liveAuthIdentity.identity,
                    rhsEmail: liveAuthIdentity.email)
        }
    }

    private func findPersistedRepairMatch(
        in candidates: [PreparedStoredManagedAccount])
        -> (destination: PreparedStoredManagedAccount, reason: CodexDisplacedLivePreservationRepairReason)?
    {
        if let destination = candidates.first(where: { $0.persisted.effectiveWorkspaceAccountID != nil }),
           let reason = self.providerRepairReason(for: destination)
        {
            return (destination, reason)
        }
        guard let destination = candidates.first(where: { $0.persisted.effectiveWorkspaceAccountID == nil }) else {
            return nil
        }
        return (destination, .persistedLegacyEmailMatch)
    }

    private func hasConflictingReadableHome(
        in candidates: [PreparedStoredManagedAccount],
        liveAuthIdentity: PreparedIdentity) -> Bool
    {
        candidates.contains { candidate in
            guard let candidateIdentity = candidate.authIdentity else { return false }
            return !CodexIdentityMatcher.matches(
                candidateIdentity.identity,
                lhsEmail: candidateIdentity.email,
                liveAuthIdentity.identity,
                rhsEmail: liveAuthIdentity.email)
        }
    }

    private func providerRepairReason(
        for destination: PreparedStoredManagedAccount)
        -> CodexDisplacedLivePreservationRepairReason?
    {
        switch destination.homeState {
        case .missing:
            .persistedProviderMatchWithMissingHome
        case .unreadable:
            .persistedProviderMatchWithUnreadableHome
        case .readable:
            nil
        }
    }
}
