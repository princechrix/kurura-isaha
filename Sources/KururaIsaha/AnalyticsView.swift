import AppKit
import KururaCore
import SwiftUI
import UniformTypeIdentifiers

/// Where the focused hours went.
///
/// The charts are hand-drawn rather than pulled from the Charts framework: a heatmap and
/// a handful of bars is less code than configuring a chart library, and it keeps the whole
/// app to zero package dependencies.
struct AnalyticsView: View {
    let store: SessionStore
    @ObservedObject var engine: TimerEngine

    private static let gridDays = 84

    @State private var days: [DayStat] = []
    @State private var tags: [TagStat] = []
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                summary
                heatmap
                breakdown
                footer
            }
            .padding(22)
        }
        .onAppear(perform: reload)
        .onReceive(engine.$timers) { _ in reload() }
    }

    // MARK: - Summary

    private var summary: some View {
        HStack(spacing: 12) {
            card("Today", DurationFormat.short(today), "\(todaySessions) session\(todaySessions == 1 ? "" : "s")")
            card("This week", DurationFormat.short(week), "\(weekSessions) session\(weekSessions == 1 ? "" : "s")")
            card("Streak", "\(streak)d", streak == 0 ? "start one today" : "consecutive days")
            card("Best day", DurationFormat.short(best), "in the last 12 weeks")
        }
    }

    private func card(_ title: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    // MARK: - Heatmap

    private var heatmap: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Focused time, last 12 weeks").font(.headline)
            HStack(alignment: .top, spacing: 3) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 3) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(colour(for: day))
                                .frame(width: 12, height: 12)
                                .help(tooltip(for: day))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 5) {
                Text("less").font(.system(size: 9)).foregroundStyle(.tertiary)
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(ramp(level))
                        .frame(width: 12, height: 12)
                }
                Text("more").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    private var weeks: [[DayStat?]] {
        guard let first = days.first, let firstDate = Self.parse(first.day) else { return [] }
        let calendar = Calendar.current
        let leading = (calendar.component(.weekday, from: firstDate) - calendar.firstWeekday + 7) % 7
        var cells: [DayStat?] = Array(repeating: nil, count: leading) + days.map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<($0 + 7)]) }
    }

    private func colour(for day: DayStat?) -> Color {
        guard let day else { return .clear }
        guard best > 0, day.seconds > 0 else { return Color.primary.opacity(0.07) }
        return ramp(min(1, day.seconds / best))
    }

    private func ramp(_ level: Double) -> Color {
        guard level > 0 else { return Color.primary.opacity(0.07) }
        return Color(PullPalette.brief).opacity(0.22 + 0.78 * level)
    }

    private func tooltip(for day: DayStat?) -> String {
        guard let day else { return "" }
        guard day.seconds > 0 else { return "\(day.day) — nothing" }
        return "\(day.day) — \(DurationFormat.short(day.seconds)) over \(day.sessions) session\(day.sessions == 1 ? "" : "s")"
    }

    // MARK: - Tags

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where it went").font(.headline)
            if tags.isEmpty {
                Text("No finished sessions yet. Pull a timer out of the menu bar to start one.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tags, id: \.tag) { tag in
                    HStack(spacing: 10) {
                        Text(tag.tag)
                            .font(.system(size: 11))
                            .frame(width: 130, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.06))
                                Capsule()
                                    .fill(Color(PullPalette.color(forDuration: tag.seconds / Double(max(1, tag.sessions)))))
                                    .frame(width: geometry.size.width * share(tag))
                            }
                        }
                        .frame(height: 10)
                        Text(DurationFormat.short(tag.seconds))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func share(_ tag: TagStat) -> Double {
        let top = tags.map(\.seconds).max() ?? 0
        return top > 0 ? min(1, tag.seconds / top) : 0
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Export CSV…", action: export)
            if let notice {
                Text(notice).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(ControlPaths.databaseURL.path)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "kurura-sessions.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportCSV(to: url)
            notice = "Saved to \(url.lastPathComponent)"
        } catch {
            notice = error.localizedDescription
        }
    }

    // MARK: - Derived numbers

    private var today: TimeInterval { days.last?.seconds ?? 0 }
    private var todaySessions: Int { days.last?.sessions ?? 0 }
    private var week: TimeInterval { days.suffix(7).reduce(0) { $0 + $1.seconds } }
    private var weekSessions: Int { days.suffix(7).reduce(0) { $0 + $1.sessions } }
    private var best: TimeInterval { days.map(\.seconds).max() ?? 0 }

    private var streak: Int {
        var count = 0
        for day in days.reversed() {
            guard day.seconds > 0 else { break }
            count += 1
        }
        return count
    }

    private func reload() {
        days = store.dayStats(days: Self.gridDays)
        tags = store.tagStats(days: 30)
    }

    private static func parse(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }
}
