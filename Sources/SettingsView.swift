import Cocoa
import SwiftUI

// MARK: - 设置面板（右键灵动岛打开）

class SettingsModel: ObservableObject {
    var isRefreshing = false   // 从配置同步值时不触发保存

    @Published var paused = false { didSet { changed() } }
    @Published var launchAtLogin = false { didSet { changed() } }
    @Published var islandEnabled = true { didSet { changed() } }
    @Published var waterMinutes = 45 { didSet { changed() } }
    @Published var standMinutes = 60 { didSet { changed() } }
    @Published var repeatMinutes = 15 { didSet { changed() } }
    @Published var breakMinutes = 5 { didSet { changed() } }
    @Published var quietPeriods: [[Int]] = [] { didSet { changed() } }
    @Published var reminderStyle: ReminderStyle = .notch { didSet { changed() } }

    private func changed() { if !isRefreshing { onChanged() } }

    // 动作回调（由 AppDelegate 接线）
    var onChanged: () -> Void = {}
    var onStylePreview: () -> Void = {}
    var onOpenStats: () -> Void = {}
    var onOpenDataFolder: () -> Void = {}
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

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var onClose: () -> Void

    let quietPresets: [(start: Int, end: Int, zh: String, en: String)] = [
        (12, 14, "午休 12–14 点", "Lunch 12–14"),
        (18, 22, "晚间 18–22 点", "Evening 18–22"),
        (22, 8,  "夜间 22–08 点", "Night 22–08")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 标题栏
            HStack {
                Text(L.t("设置", "Settings"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            // 开关组
            Toggle(L.t("暂停提醒", "Pause reminders"), isOn: $model.paused)
                .foregroundStyle(.white)
            Toggle(L.t("开机自动启动", "Launch at login"), isOn: $model.launchAtLogin)
                .foregroundStyle(.white)
            Toggle(L.t("灵动岛常驻显示", "Always-on island"), isOn: $model.islandEnabled)
                .foregroundStyle(.white)

            Divider().background(.white.opacity(0.15))

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

            // 免打扰多选
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("免打扰时段（可多选）", "Quiet hours (multi-select)"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
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
            }

            // 提醒方式
            OptionPills(title: L.t("提醒方式", "Reminder style"),
                        options: [(L.t("灵动岛", "Island"), 0), (L.t("强提醒", "Alert"), 1), (L.t("通知", "Banner"), 2)],
                        value: Binding(
                            get: { model.reminderStyle == .notch ? 0 : (model.reminderStyle == .strong ? 1 : 2) },
                            set: { model.reminderStyle = $0 == 0 ? .notch : ($0 == 1 ? .strong : .gentle)
                                   model.onStylePreview() }))

            Divider().background(.white.opacity(0.15))

            // 底部按钮
            HStack(spacing: 14) {
                Button(L.t("统计详情…", "Stats…")) { model.onOpenStats() }
                Button(L.t("数据文件夹", "Data folder")) { model.onOpenDataFolder() }
                Spacer()
                Button(L.t("退出", "Quit")) { model.onQuit() }
                    .foregroundStyle(.red.opacity(0.9))
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.85))
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(width: 330, height: 620)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(white: 0.09)))
        .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 6)
        .tint(.teal)
    }
}

class SettingsPanelController {
    let model = SettingsModel()
    private var panel: NSPanel?
    private var onChangeWork: DispatchWorkItem?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(actions wire: (SettingsModel) -> Void) {
        model.isRefreshing = true
        wire(model)   // 每次打开同步最新配置
        model.isRefreshing = false
        if panel == nil {
            let view = SettingsView(model: model, onClose: { [weak self] in self?.hide() })
            let hosting = NSHostingView(rootView: view)
            let size = NSSize(width: 330, height: 620)
            hosting.frame = NSRect(origin: .zero, size: size)
            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.contentView = hosting
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.appearance = NSAppearance(named: .darkAqua)   // 深色外观，开关文字用浅色
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.isReleasedWhenClosed = false
            self.panel = panel
        }
        // 贴灵动岛下方
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main {
            let h: CGFloat = 620
            let x = screen.frame.midX - 165
            let y = screen.frame.maxY - screen.safeAreaInsets.top - h - 8
            panel?.setFrame(NSRect(x: x, y: y, width: 330, height: h), display: true)
        }
        panel?.orderFrontRegardless()
    }

    func hide() { panel?.close() }
    func toggle(actions wire: (SettingsModel) -> Void) {
        isVisible ? hide() : show(actions: wire)
    }
}
