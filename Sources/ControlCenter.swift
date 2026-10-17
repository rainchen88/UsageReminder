import Cocoa
import SwiftUI

// MARK: - 控制台（右键灵动岛打开）
// 独立黑色管理窗口：设置 + 外观 + 提醒预览 + 数据统计 四页合一。
// 左侧导航栏，右侧内容区；窗口位置自动记忆。

enum ControlTab: Int, CaseIterable {
    case general, appearance, reminder, stats

    var title: String {
        switch self {
        case .general:    return L.t("通用", "General")
        case .appearance: return L.t("外观", "Appearance")
        case .reminder:   return L.t("提醒", "Reminders")
        case .stats:      return L.t("统计", "Stats")
        }
    }
    var icon: String {
        switch self {
        case .general:    return "gearshape"
        case .appearance: return "rectangle.expand.vertical"
        case .reminder:   return "bell.badge"
        case .stats:      return "chart.bar"
        }
    }
}

class ControlCenterModel: ObservableObject {
    var isRefreshing = false   // 从配置同步值时不触发保存

    @Published var tab: ControlTab = .general

    // 通用
    @Published var paused = false { didSet { changed() } }
    @Published var launchAtLogin = false { didSet { changed() } }
    @Published var islandEnabled = true { didSet { changed() } }
    @Published var waterMinutes = 45 { didSet { changed() } }
    @Published var standMinutes = 60 { didSet { changed() } }
    @Published var repeatMinutes = 15 { didSet { changed() } }
    @Published var breakMinutes = 5 { didSet { changed() } }
    @Published var quietPeriods: [[Int]] = [] { didSet { changed() } }
    @Published var escalateReminders = true { didSet { changed() } }
    @Published var breakPraiseEnabled = true { didSet { changed() } }
    @Published var fullscreenPause = true { didSet { changed() } }
    @Published var weeklyReportEnabled = true { didSet { changed() } }

    // 外观（滑条实时预览）
    @Published var islandWidth: Double = 320 { didSet { changed() } }
    @Published var expandedHeight: Double = 122 { didSet { changed() } }
    @Published var pillPadding: Double = 20 { didSet { changed() } }

    // 提醒
    @Published var reminderStyle: ReminderStyle = .notch { didSet { changed() } }
    @Published var waterTitle = "" { didSet { changed() } }
    @Published var waterMessage = "" { didSet { changed() } }
    @Published var standTitle = "" { didSet { changed() } }
    @Published var standMessage = "" { didSet { changed() } }

    // 统计快照（由 AppDelegate 填充）
    @Published var bars: [DayBar] = []
    @Published var todayStats = DayStats()
    @Published var currentContinuous: TimeInterval = 0
    @Published var weekTotal: TimeInterval = 0

    private func changed() { if !isRefreshing { onChanged() } }

    // 动作回调（由 AppDelegate 接线）
    var onChanged: () -> Void = {}
    var onStylePreview: () -> Void = {}
    var onPreview: (String) -> Void = { _ in }   // water / stand / escalated / celebration / weekly
    var onRefreshStats: () -> Void = {}
    var onOpenDataFolder: () -> Void = {}
    var onExportData: () -> Void = {}
    var onQuit: () -> Void = {}
}

// 胶囊选项行（单选）
struct OptionPills: View {
    let title: String
    let options: [(label: String, value: Int)]
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 6) {
                ForEach(options, id: \.value) { opt in
                    Button(action: { value = opt.value }) {
                        Text(opt.label)
                            .font(.system(size: 12, weight: value == opt.value ? .semibold : .regular))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(value == opt.value ? Color.white.opacity(0.22) : Color.white.opacity(0.07))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// 分区标题
struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.45))
            .textCase(nil)
    }
}

struct ControlCenterView: View {
    @ObservedObject var model: ControlCenterModel

    let quietPresets: [(start: Int, end: Int, zh: String, en: String)] = [
        (12, 14, "午休 12–14 点", "Lunch 12–14"),
        (18, 22, "晚间 18–22 点", "Evening 18–22"),
        (22, 8,  "夜间 22–08 点", "Night 22–08")
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1)
            content
        }
        .background(Color(white: 0.07))
    }

    // MARK: 左侧导航

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "figure.seated.side")
                    .foregroundStyle(.teal)
                Text(L.t("久坐提醒", "UsageReminder"))
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ForEach(ControlTab.allCases, id: \.rawValue) { t in
                Button(action: {
                    model.tab = t
                    if t == .stats { model.onRefreshStats() }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: t.icon)
                            .frame(width: 16)
                        Text(t.title)
                            .font(.system(size: 13, weight: model.tab == t ? .semibold : .regular))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(model.tab == t ? Color.white.opacity(0.14) : Color.clear)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())   // 整行都可点击，不必精准点中文字
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            Spacer()
        }
        .frame(width: 168)
        .background(Color(white: 0.1))
    }

    // MARK: 右侧内容

    var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch model.tab {
                case .general:    generalPage
                case .appearance: appearancePage
                case .reminder:   reminderPage
                case .stats:      statsPage
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 通用

    var generalPage: some View {
        Group {
            SectionTitle(text: L.t("开关", "Switches"))
            Toggle(L.t("暂停提醒", "Pause reminders"), isOn: $model.paused)
            Toggle(L.t("开机自动启动", "Launch at login"), isOn: $model.launchAtLogin)
            Toggle(L.t("灵动岛常驻显示", "Always-on island"), isOn: $model.islandEnabled)

            Divider().background(.white.opacity(0.15))

            SectionTitle(text: L.t("智能行为", "Smart behavior"))
            Toggle(L.t("提醒被忽略后逐渐加强", "Escalate ignored reminders"), isOn: $model.escalateReminders)
            Toggle(L.t("休息打卡鼓励", "Break celebration"), isOn: $model.breakPraiseEnabled)
            Toggle(L.t("全屏时自动免打扰（会议/视频）", "Auto quiet when fullscreen"), isOn: $model.fullscreenPause)
            Toggle(L.t("每周一健康报告", "Weekly report on Mondays"), isOn: $model.weeklyReportEnabled)

            Divider().background(.white.opacity(0.15))

            SectionTitle(text: L.t("提醒阈值", "Thresholds"))
            OptionPills(title: L.t("喝水提醒（分钟）", "Water reminder (min)"),
                        options: [(L.t("关", "Off"), 0), ("30", 30), ("45", 45), ("60", 60), ("90", 90)],
                        value: $model.waterMinutes)
            OptionPills(title: L.t("站立提醒（分钟）", "Stand reminder (min)"),
                        options: [(L.t("关", "Off"), 0), ("45", 45), ("60", 60), ("75", 75), ("90", 90)],
                        value: $model.standMinutes)
            OptionPills(title: L.t("重复提醒间隔（分钟）", "Repeat every (min)"),
                        options: [("10", 10), ("15", 15), ("20", 20), ("30", 30)],
                        value: $model.repeatMinutes)
            OptionPills(title: L.t("休息判定：无操作多久算休息（分钟）", "Break threshold (idle min)"),
                        options: [("3", 3), ("5", 5), ("8", 8), ("10", 10)],
                        value: $model.breakMinutes)

            Divider().background(.white.opacity(0.15))

            SectionTitle(text: L.t("免打扰时段（可多选）", "Quiet hours (multi-select)"))
            HStack(spacing: 6) {
                ForEach(quietPresets, id: \.start) { p in
                    let on = model.quietPeriods.contains([p.start, p.end])
                    Button(action: {
                        if let idx = model.quietPeriods.firstIndex(of: [p.start, p.end]) {
                            model.quietPeriods.remove(at: idx)
                        } else {
                            model.quietPeriods.append([p.start, p.end])
                        }
                    }) {
                        Text(L.t(p.zh, p.en))
                            .font(.system(size: 12, weight: on ? .semibold : .regular))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(on ? Color.white.opacity(0.22) : Color.white.opacity(0.07))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().background(.white.opacity(0.15))

            HStack(spacing: 16) {
                Button(L.t("导出数据…", "Export…")) { model.onExportData() }
                Button(L.t("数据文件夹", "Data folder")) { model.onOpenDataFolder() }
                Spacer()
                Button(L.t("退出", "Quit")) { model.onQuit() }
                    .foregroundStyle(.red.opacity(0.9))
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.85))
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
    }

    // MARK: 外观

    var appearancePage: some View {
        Group {
            SectionTitle(text: L.t("灵动岛尺寸（拖动实时预览）", "Island size (live preview)"))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L.t("胶囊宽度", "Capsule width"))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Text("\(Int(model.islandWidth)) pt")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                }
                Slider(value: $model.islandWidth, in: 240...560, step: 5)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L.t("展开看板高度", "Expanded height"))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Text("\(Int(model.expandedHeight)) pt")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                }
                Slider(value: $model.expandedHeight, in: 90...200, step: 2)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L.t("文字离左右边缘距离", "Edge padding"))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Text("\(Int(model.pillPadding)) pt")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                }
                Slider(value: $model.pillPadding, in: 8...100, step: 2)
            }

            HStack {
                Button(L.t("恢复默认尺寸", "Reset size")) {
                    model.islandWidth = 320
                    model.expandedHeight = 122
                    model.pillPadding = 20
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                Spacer()
            }

            Text(L.t("胶囊高度始终与刘海齐平；宽度越宽，刘海两侧的「耳朵」内容越宽松。",
                     "Capsule height always matches the notch; a wider capsule gives the side ears more room."))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 提醒（方式 + 文案 + 预览）

    var reminderPage: some View {
        Group {
            SectionTitle(text: L.t("提醒方式", "Reminder style"))
            OptionPills(title: "",
                        options: [(L.t("灵动岛", "Island"), 0), (L.t("强提醒", "Alert"), 1), (L.t("通知", "Banner"), 2)],
                        value: Binding(
                            get: { model.reminderStyle == .notch ? 0 : (model.reminderStyle == .strong ? 1 : 2) },
                            set: { model.reminderStyle = $0 == 0 ? .notch : ($0 == 1 ? .strong : .gentle)
                                   model.onStylePreview() }))

            Divider().background(.white.opacity(0.15))

            SectionTitle(text: L.t("自定义文案（留空用默认，正文支持 {分钟} 占位符）",
                                   "Custom text (blank = default; {分钟} = minutes)"))
            customTextEditor(kindTitle: L.t("喝水提醒", "Water"),
                             title: $model.waterTitle, message: $model.waterMessage,
                             defaultTitle: L.t("喝口水吧 💧", "Drink some water 💧"),
                             defaultMessage: L.t("已连续使用 {分钟} 分钟。…", "Active for {分钟} minutes. …"))
            customTextEditor(kindTitle: L.t("站立提醒", "Stand"),
                             title: $model.standTitle, message: $model.standMessage,
                             defaultTitle: L.t("该起来活动了 🧍", "Time to stand up 🧍"),
                             defaultMessage: L.t("已连续使用 {分钟} 分钟。…", "Active for {分钟} minutes. …"))

            Divider().background(.white.opacity(0.15))

            SectionTitle(text: L.t("效果预览（点一下，真实弹一次）", "Preview (fires a real one)"))
            HStack(spacing: 8) {
                previewButton("drop.fill", L.t("喝水", "Water"), "water")
                previewButton("figure.stand", L.t("站立", "Stand"), "stand")
                previewButton("exclamationmark.triangle.fill", L.t("升级版", "Escalated"), "escalated")
            }
            HStack(spacing: 8) {
                previewButton("checkmark.circle.fill", L.t("休息打卡", "Break"), "celebration")
                previewButton("chart.bar.doc.horizontal", L.t("周报", "Weekly"), "weekly")
            }
        }
        .foregroundStyle(.white)
    }

    func customTextEditor(kindTitle: String, title: Binding<String>, message: Binding<String>,
                          defaultTitle: String, defaultMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kindTitle)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
            TextField(defaultTitle, text: title)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            TextField(defaultMessage, text: message)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
    }

    func previewButton(_ icon: String, _ label: String, _ kind: String) -> some View {
        Button(action: { model.onPreview(kind) }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.08))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: 统计

    var statsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatsView(days: model.bars, today: model.todayStats,
                      currentContinuous: model.currentContinuous, weekTotal: model.weekTotal)
            HStack {
                Button(action: { model.onRefreshStats() }) {
                    Label(L.t("刷新", "Refresh"), systemImage: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.85))
                Spacer()
            }
        }
    }
}

// MARK: - 窗口控制器

class ControlCenterController {
    let model = ControlCenterModel()
    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible ?? false }

    func toggle(actions wire: (ControlCenterModel) -> Void) {
        isVisible ? close() : show(actions: wire)
    }

    func show(actions wire: (ControlCenterModel) -> Void, tab: ControlTab? = nil) {
        model.isRefreshing = true
        wire(model)
        if let tab = tab { model.tab = tab }
        model.isRefreshing = false
        model.onRefreshStats()

        if window == nil {
            let view = ControlCenterView(model: model)
            let hosting = NSHostingView(rootView: view)
            let size = NSSize(width: 780, height: 560)
            hosting.frame = NSRect(origin: .zero, size: size)
            let win = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                               styleMask: [.titled, .closable, .miniaturizable],
                               backing: .buffered, defer: false)
            win.contentView = hosting
            win.title = L.t("久坐提醒 · 控制台", "UsageReminder · Control Center")
            win.titlebarAppearsTransparent = true
            win.backgroundColor = NSColor(white: 0.07, alpha: 1)
            win.appearance = NSAppearance(named: .darkAqua)
            win.isReleasedWhenClosed = false
            win.setFrameAutosaveName("UsageReminderControlCenter")
            if !win.setFrameUsingName("UsageReminderControlCenter") { win.center() }
            self.window = win
        }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.close() }
}
