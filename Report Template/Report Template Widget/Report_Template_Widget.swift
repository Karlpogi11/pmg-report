import SwiftUI
import WidgetKit

struct ReportTemplateEntry: TimelineEntry {
    let date: Date
}

struct ReportTemplateTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReportTemplateEntry {
        ReportTemplateEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (ReportTemplateEntry) -> Void) {
        completion(ReportTemplateEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReportTemplateEntry>) -> Void) {
        let now = Date()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now
        let timeline = Timeline(entries: [ReportTemplateEntry(date: now)], policy: .after(nextRefresh))
        completion(timeline)
    }
}

struct ReportTemplateWidgetEntryView: View {
    var entry: ReportTemplateEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PMG Report")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Ready to continue")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(entry.date, style: .time)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .containerBackground(for: .widget) {
            Color(.windowBackgroundColor)
        }
    }
}

struct ReportTemplateWidget: Widget {
    let kind = "ReportTemplateWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ReportTemplateTimelineProvider()) { entry in
            ReportTemplateWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Report Snapshot")
        .description("Quick glance status for PMG Report.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
