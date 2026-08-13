import SwiftUI
import WidgetKit

@main
struct DexoWidgetBundle: WidgetBundle {
    var body: some Widget {
        DexoQuickActionsWidget()
    }
}

struct DexoQuickActionsWidget: Widget {
    let kind = "DexoQuickActionsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            DexoQuickActionsView(entry: entry)
                .widgetURL(URL(string: "doer://read-later"))
        }
        .configurationDisplayName(String(localized: "widget.quick.title", defaultValue: "Doer 快捷入口"))
        .description(String(localized: "widget.quick.desc", defaultValue: "稍后阅读与通知快捷入口"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let entry = SimpleEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
}

struct DexoQuickActionsView: View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Doer")
                .font(.headline)
            Text(String(localized: "widget.quick.subtitle", defaultValue: "稍后阅读 · 通知"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Link(destination: URL(string: "doer://read-later")!) {
                    Label(String(localized: "me.read_later", defaultValue: "稍后阅读"), systemImage: "clock")
                        .font(.caption.weight(.semibold))
                        .padding(8)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Link(destination: URL(string: "doer://notifications")!) {
                    Label(String(localized: "tab.notifications", defaultValue: "通知"), systemImage: "bell")
                        .font(.caption.weight(.semibold))
                        .padding(8)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding()
    }
}
