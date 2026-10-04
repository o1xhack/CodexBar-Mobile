import SwiftUI

// Inside a Link, hierarchical styles such as `.primary` resolve to the
// tint, so text uses the system label colors explicitly.

/// Other apps and projects by the developer, mirroring app.o1xhack.com.
/// Each row opens the App Store page when the project ships an iOS app,
/// otherwise its website, otherwise its GitHub repository.
struct MoreAppsView: View {
    static let portfolioURL = URL(string: "https://app.o1xhack.com")!

    var body: some View {
        List {
            Section {
                ForEach(MoreAppItem.projects) { item in
                    Link(destination: item.url) {
                        MoreAppRow(item: item)
                    }
                    .accessibilityIdentifier("more-apps-\(item.id)")
                }
            } header: {
                Text("Apps & Projects")
            }

            Section {
                ForEach(MoreAppItem.obsidianPlugins) { item in
                    Link(destination: item.url) {
                        HStack {
                            Text(item.name)
                                .foregroundStyle(Color(.label))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                    }
                    .accessibilityIdentifier("more-apps-\(item.id)")
                }
            } header: {
                Text("Obsidian Plugins")
            } footer: {
                Link(destination: Self.portfolioURL) {
                    Text("See everything at app.o1xhack.com")
                        .font(.footnote)
                }
                .padding(.top, 4)
            }
        }
        .navigationTitle("More Apps")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MoreAppItem: Identifiable {
    enum Destination {
        case appStore
        case website
        case github

        var title: LocalizedStringResource {
            switch self {
            case .appStore: "App Store"
            case .website: "Website"
            case .github: "GitHub"
            }
        }
    }

    let id: String
    let name: String
    let summary: LocalizedStringResource?
    let iconAsset: String?
    let destination: Destination
    let url: URL

    static let projects: [MoreAppItem] = [
        MoreAppItem(
            id: "coffee-it",
            name: "Coffee It",
            summary: "Track your daily caffeine with 200+ coffee options and Apple Health.",
            iconAsset: "MoreAppCoffeeIt",
            destination: .appStore,
            url: URL(string: "https://apps.apple.com/app/id1216049514")!),
        MoreAppItem(
            id: "photo-status",
            name: "Photo Status",
            summary: "See which iCloud Photos originals are missing from your device and download them.",
            iconAsset: "MoreAppPhotoStatus",
            destination: .appStore,
            url: URL(string: "https://apps.apple.com/app/id6784043470")!),
        MoreAppItem(
            id: "scrobble-bridge",
            name: "Scrobble Bridge",
            summary: "Sync your YouTube Music listening history to Last.fm with a local-first Mac app.",
            iconAsset: "MoreAppScrobbleBridge",
            destination: .website,
            url: URL(string: "https://scrobble-bridge.o1xhack.com")!),
        MoreAppItem(
            id: "telegram-watch",
            name: "Telegram Watch",
            summary: "An open-source, self-hosted Telegram monitor that sends periodic reports.",
            iconAsset: "MoreAppTelegramWatch",
            destination: .github,
            url: URL(string: "https://github.com/o1xhack/telegram-watch")!),
    ]

    static let obsidianPlugins: [MoreAppItem] = [
        Self.obsidianPlugin(id: "obsidian-chatting", name: "Chatting with AI", slug: "chatting-with-ai"),
        Self.obsidianPlugin(id: "obsidian-daily-note-plus", name: "Daily Note Plus", slug: "daily-note-plus"),
        Self.obsidianPlugin(id: "obsidian-sync-todoist", name: "Sync Todoist", slug: "sync-todoist"),
        Self.obsidianPlugin(id: "obsidian-sync-trakt", name: "Sync Trakt", slug: "sync-trakt"),
    ]

    private static func obsidianPlugin(id: String, name: String, slug: String) -> MoreAppItem {
        MoreAppItem(
            id: id,
            name: name,
            summary: nil,
            iconAsset: nil,
            destination: .website,
            url: URL(string: "https://community.obsidian.md/plugins/\(slug)")!)
    }
}

private struct MoreAppRow: View {
    let item: MoreAppItem

    var body: some View {
        HStack(spacing: 12) {
            if let iconAsset = self.item.iconAsset {
                Image(iconAsset)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 0.5)
                    }
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(self.item.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(.label))
                if let summary = self.item.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(Color(.secondaryLabel))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 3) {
                Text(self.item.destination.title)
                Image(systemName: "arrow.up.right")
            }
            .font(.caption)
            .foregroundStyle(.tint)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
