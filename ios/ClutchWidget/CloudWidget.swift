import SwiftUI
import WidgetKit

struct CloudEntry: TimelineEntry {
    let date: Date
    let moment: MascotMoment
}

struct CloudProvider: TimelineProvider {
    func placeholder(in context: Context) -> CloudEntry {
        CloudEntry(date: .now, moment: MascotMoment(scene: .walk, line: MascotScene.walk.line, caption: "Day 12 \u{b7} period in 16 days", hasFlower: false))
    }

    func getSnapshot(in context: Context, completion: @escaping (CloudEntry) -> Void) {
        completion(entry(at: .now))
    }

    /// One entry now and one at every scene change through tomorrow; then
    /// WidgetKit asks again.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CloudEntry>) -> Void) {
        let now = Date.now
        let snapshot = CycleSnapshot.load()
        let dates = [now] + MascotMoment.changeTimes(from: now)
        let entries = dates.map { CloudEntry(date: $0, moment: MascotMoment.make(at: $0, snapshot: snapshot)) }
        completion(Timeline(entries: entries, policy: .after(dates.last ?? now.addingTimeInterval(3600))))
    }

    private func entry(at date: Date) -> CloudEntry {
        CloudEntry(date: date, moment: MascotMoment.make(at: date, snapshot: CycleSnapshot.load()))
    }
}

struct CloudWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CloudEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium: medium
            case .accessoryRectangular: rectangular
            default: small
            }
        }
        .widgetURL(URL(string: "clutch://\(entry.moment.route)"))
    }

    private var scene: some View {
        MascotSceneView(scene: entry.moment.scene, hasFlower: entry.moment.hasFlower, sparkle: entry.moment.sparkle)
    }

    private var small: some View {
        scene
            .overlay(alignment: .bottomLeading) {
                Text(entry.moment.line)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(CloudPalette.ink)
                    .lineLimit(2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(8)
            }
            .containerBackground(for: .widget) { Color.clear }
    }

    private var medium: some View {
        HStack(spacing: 0) {
            scene
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                if let caption = entry.moment.caption {
                    Text(caption.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(CloudPalette.matcha)
                }
                Text(entry.moment.line)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(CloudPalette.ink)
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text(entry.moment.hasFlower ? "Logged today \u{2713}" : "Tap to log today")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(CloudPalette.ink.opacity(0.6))
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(red: 0.98, green: 0.96, blue: 0.94))
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var rectangular: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.moment.scene == .drizzle ? "cloud.drizzle.fill" : "cloud.fill")
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                if let caption = entry.moment.caption {
                    Text(caption).font(.caption2.weight(.semibold))
                }
                Text(entry.moment.line).font(.caption2).lineLimit(2)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct CloudWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ClutchShared.widgetKind, provider: CloudProvider()) { entry in
            CloudWidgetView(entry: entry)
        }
        .configurationDisplayName("Clutch cloud")
        .description("Your little cloud, going about its day and keeping an eye on your cycle.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

@main
struct ClutchWidgetBundle: WidgetBundle {
    var body: some Widget {
        CloudWidget()
    }
}
