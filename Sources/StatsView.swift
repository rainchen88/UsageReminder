import SwiftUI
import Charts

// MARK: - 统计详情窗口（SwiftUI）

struct DayBar: Identifiable {
    let id = UUID()
    let label: String
    let minutes: Double
    let isToday: Bool
}

struct StatsView: View {
    let days: [DayBar]
    let today: DayStats
    let currentContinuous: TimeInterval
    let weekTotal: TimeInterval   // 近 7 天累计（含今天）

    var weekAverage: TimeInterval {
        let activeDays = max(days.filter { $0.minutes > 0 }.count, 1)
        return weekTotal / Double(activeDays)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "figure.seated.side")
                    .font(.title2)
                    .foregroundStyle(.teal)
                Text(L.t("使用统计", "Usage Stats"))
                    .font(.title2).bold()
                Spacer()
            }

            HStack {
                Text(L.t("近 7 天累计使用时长", "Screen time · last 7 days"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if weekTotal > 0 {
                    Text(L.t("共 \(fmtDuration(weekTotal)) · 日均 \(fmtDuration(weekAverage))",
                             "Total \(fmtDuration(weekTotal)) · avg \(fmtDuration(weekAverage))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Chart(days) { d in
                BarMark(
                    x: .value(L.t("日期", "Day"), d.label),
                    y: .value(L.t("分钟", "Minutes"), d.minutes)
                )
                .foregroundStyle(d.isToday ? Color.orange.gradient : Color.teal.gradient)
                .cornerRadius(4)
            }
            .chartYAxisLabel(L.t("分钟", "min"))
            .frame(height: 180)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(L.t("今日", "Today")).font(.headline)
                statRow(L.t("累计使用", "Total active"), fmtDuration(today.totalActiveSeconds))
                statRow(L.t("当前连续", "Current streak"),
                        currentContinuous > 0 ? fmtDuration(currentContinuous) : L.t("休息中", "Resting"))
                statRow(L.t("连续使用段", "Sessions"), "\(today.sessions.count)")
                statRow(L.t("最长一段", "Longest"), fmtDuration(today.longestSessionSeconds))
                statRow(L.t("喝水 / 站立提醒", "Water / Stand alerts"), "\(today.waterReminders) / \(today.standReminders)")
                statRow(L.t("已完成休息", "Breaks taken"), "\(today.breaks)")
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold()
        }
        .font(.callout)
    }
}
