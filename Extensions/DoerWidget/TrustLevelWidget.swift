import SwiftUI
import WidgetKit

struct TrustLevelWidget: Widget {
    let kind = TrustLevelWidgetIDs.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrustLevelProvider()) { entry in
            TrustLevelWidgetView(entry: entry)
                .widgetURL(URL(string: TrustLevelWidgetIDs.deepLink))
        }
        .configurationDisplayName(String(localized: "trust.widget.title", defaultValue: "信任等级"))
        .description(String(localized: "trust.widget.desc", defaultValue: "已读帖子与升到下一级还差多少"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TrustLevelProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrustLevelEntry {
        TrustLevelEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TrustLevelEntry) -> Void) {
        completion(TrustLevelEntry(date: Date(), snapshot: TrustLevelWidgetSnapshotStore.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrustLevelEntry>) -> Void) {
        let snapshot = TrustLevelWidgetSnapshotStore.load()
        let entry = TrustLevelEntry(date: Date(), snapshot: snapshot)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct TrustLevelEntry: TimelineEntry {
    let date: Date
    let snapshot: TrustLevelWidgetSnapshot?
}

private extension TrustLevelWidgetSnapshot {
    static let placeholder = TrustLevelWidgetSnapshot(
        title: String(localized: "trust.widget.title", defaultValue: "信任等级"),
        badgeText: "TL2",
        subtitle: "",
        items: [
            TrustLevelWidgetItem(label: String(localized: "trust.widget.posts_read", defaultValue: "已读帖子"), current: 1200, target: 20000, isMet: false, isReverse: false)
        ],
        updatedAt: Date(),
        trustLevel: 2
    )
}

struct TrustLevelWidgetView: View {
    var entry: TrustLevelEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                content(snapshot)
            } else {
                emptyState
            }
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "trust.widget.title", defaultValue: "信任等级"))
                .font(.headline)
            Text(String(localized: "trust.widget.empty", defaultValue: "打开 App 后同步等级进度"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func content(_ snapshot: TrustLevelWidgetSnapshot) -> some View {
        switch family {
        case .systemMedium:
            mediumContent(snapshot)
        default:
            smallContent(snapshot)
        }
    }

    private func smallContent(_ snapshot: TrustLevelWidgetSnapshot) -> some View {
        let item = snapshot.headlineItem
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(snapshot.badgeText.isEmpty ? snapshot.title : snapshot.badgeText)
                    .font(.headline)
                Spacer()
                if let level = snapshot.trustLevel {
                    Text("TL\(level)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if let item {
                Text(item.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: progress(item))
                Text(progressCaption(item))
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
            }
        }
    }

    private func mediumContent(_ snapshot: TrustLevelWidgetSnapshot) -> some View {
        let items = displayItems(snapshot)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(snapshot.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(snapshot.badgeText.isEmpty ? (snapshot.trustLevel.map { "TL\($0)" } ?? "") : snapshot.badgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.label)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(progressCaption(item))
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                    }
                    ProgressView(value: progress(item))
                }
            }
        }
    }

    /// Prefer 已读帖子 (or first unmet) so the medium widget matches the PRD headline.
    private func displayItems(_ snapshot: TrustLevelWidgetSnapshot) -> [TrustLevelWidgetItem] {
        guard let headline = snapshot.headlineItem else {
            return Array(snapshot.items.prefix(3))
        }
        let rest = snapshot.items.filter { $0.label != headline.label }
        return Array(([headline] + rest).prefix(3))
    }

    private func progress(_ item: TrustLevelWidgetItem) -> Double {
        guard item.target > 0 else { return item.isMet ? 1 : 0 }
        if item.isReverse {
            return min(max(Double(item.target) / Double(max(item.current, 1)), 0), 1)
        }
        return min(max(Double(item.current) / Double(item.target), 0), 1)
    }

    private func progressCaption(_ item: TrustLevelWidgetItem) -> String {
        if item.isMet {
            let metText = String(localized: "trust.widget.met", defaultValue: "已达标")
            if item.isReverse {
                return "\(item.current) / ≤ \(item.target) · \(metText)"
            }
            return "\(item.current) / \(item.target) · \(metText)"
        }
        if item.isReverse {
            return String(localized: "trust.widget.keep_under", defaultValue: "需保持 ≤ \(item.target)")
        }
        return String(localized: "trust.widget.remaining", defaultValue: "\(item.current) / 还差 \(item.remaining)")
    }
}
