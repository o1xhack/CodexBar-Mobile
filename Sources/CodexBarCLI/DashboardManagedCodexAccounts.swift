import CodexBarCore
import Foundation

/// Reads app-owned metadata and retained usage only; never opens managed homes or credentials.
enum DashboardManagedCodexAccounts {
    /// Provider-specific by design: this adapter owns Codex's saved managed-account metadata and usage.
    private static let provider = UsageProvider.codex

    private struct Cache: Decodable {
        let version: Int
        let records: [Record]
    }

    private struct Record: Decodable {
        struct Identity: Decodable {
            let normalizedEmail: String?
            let workspaceAccountID: String?
            let storedAccountID: UUID?
        }

        let accountIdentity: Identity?
        let snapshot: UsageSnapshot?
        let error: String?

        private enum CodingKeys: String, CodingKey { case accountIdentity, snapshot, error }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self.accountIdentity = try? values.decode(Identity.self, forKey: .accountIdentity)
            self.snapshot = try? values.decode(UsageSnapshot.self, forKey: .snapshot)
            self.error = try? values.decode(String.self, forKey: .error)
        }

        func matches(_ account: ManagedCodexAccount) -> Bool {
            guard let identity = self.accountIdentity,
                  identity.storedAccountID == account.id,
                  CodexIdentityResolver.normalizeEmail(identity.normalizedEmail) == account.email,
                  let workspace = account.effectiveWorkspaceAccountID,
                  ManagedCodexAccount.normalizeWorkspaceAccountID(identity.workspaceAccountID) == workspace
            else { return false }
            return self.snapshot?.identity?.providerID == nil || self.snapshot?.identity?
                .providerID == DashboardManagedCodexAccounts.provider.instanceID
        }
    }

    static func collect(
        config: CodexBarConfig,
        accountStoreURL: URL = FileManagedCodexAccountStore.defaultURL()) -> DashboardAccountsInput?
    {
        guard config.enabledProviders().compactMap(\.firstPartyProvider).contains(self.provider) else { return nil }
        let accounts: [ManagedCodexAccount]
        do {
            accounts = try FileManagedCodexAccountStore(fileURL: accountStoreURL).loadAccountMetadata().accounts
        } catch {
            return DashboardAccountsInput(
                accounts: nil, adapterError: "Could not read managed Codex account metadata.", weeklyWorkDays: nil)
        }
        guard !accounts.isEmpty else { return nil }
        let cacheURL = accountStoreURL.deletingLastPathComponent()
            .appendingPathComponent("codex-account-snapshots.json")
        let records: [Record]
        do {
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                let cache = try JSONDecoder().decode(Cache.self, from: Data(contentsOf: cacheURL))
                guard cache.version == 1 else {
                    return DashboardAccountsInput(
                        accounts: nil, adapterError: "Unsupported saved Codex usage version.", weeklyWorkDays: nil)
                }
                records = cache.records
            } else {
                records = []
            }
        } catch {
            return DashboardAccountsInput(
                accounts: nil, adapterError: "Could not read saved Codex account usage.", weeklyWorkDays: nil)
        }
        let activeSource = config.providerConfig(for: Self.provider.instanceID)?.codexActiveSource ?? .liveSystem
        let visible = CodexVisibleAccountProjection(
            visibleAccounts: accounts.map { account in
                CodexVisibleAccount(
                    id: account.id.uuidString.lowercased(),
                    email: account.email,
                    workspaceLabel: account.workspaceLabel,
                    workspaceAccountID: account.effectiveWorkspaceAccountID,
                    storedAccountID: account.id,
                    selectionSource: .managedAccount(id: account.id),
                    isActive: activeSource == .managedAccount(id: account.id),
                    isLive: false,
                    canReauthenticate: false,
                    canRemove: false)
            },
            activeVisibleAccountID: nil,
            liveVisibleAccountID: nil,
            hasUnreadableAddedAccountStore: false)
        let projected = zip(accounts, visible.visibleAccounts).map { account, label in
            let record = records.filter { $0.matches(account) }.max {
                ($0.snapshot?.updatedAt ?? .distantPast) < ($1.snapshot?.updatedAt ?? .distantPast)
            }
            // Raw refresh errors may contain paths or credential diagnostics; export only their presence.
            let error = record?.error != nil
                ? "Saved usage refresh failed. Refresh this account in CodexBar."
                : record?.snapshot == nil ? "No saved usage for this account. Refresh it in CodexBar." : nil
            return ProviderAccountUsageSnapshot(
                id: ProviderAccountIdentity(source: "codex-managed", opaqueID: label.id),
                provider: Self.provider,
                displayLabel: label.displayName,
                accountEmail: account.email,
                isActive: label.isActive,
                usesLastKnownUsage: true,
                snapshot: record?.snapshot,
                error: error,
                sourceLabel: nil)
        }
        return DashboardAccountsInput(accounts: projected, adapterError: nil, weeklyWorkDays: nil)
    }
}
