import Cocoa
import IOKit
import SwiftUI
import Charts
import ServiceManagement

// ============================================================
// 久坐提醒 · 菜单栏小工具 v2
// 监控连续电脑使用时长，强提醒喝水/站立，统计每日使用情况
// ============================================================

// MARK: - 配置

struct Config: Codable {
    var waterReminderMinutes: Int = 45   // 喝水提醒阈值（0 = 关闭）
    var standReminderMinutes: Int = 60   // 站立提醒阈值（0 = 关闭）
    var breakResetMinutes: Int = 5       // 无操作多久算「已休息」
    var repeatReminderMinutes: Int = 15  // 未休息时每隔多久重复提醒
    var paused: Bool = false
}

// MARK: - 统计数据

struct Session: Codable {
    var start: TimeInterval
    var end: TimeInterval
    var seconds: TimeInterval
}

struct DayStats: Codable {
    var totalActiveSeconds: TimeInterval = 0   // 今日累计使用（含零碎使用）
    var sessions: [Session] = []               // 连续使用段
    var waterReminders: Int = 0
    var standReminders: Int = 0
    var breaks: Int = 0                        // 实际休息次数
    var longestSessionSeconds: TimeInterval = 0
}

struct StatsStore: Codable {
    var days: [String: DayStats] = [:]
}

// MARK: - 系统空闲时间（无操作秒数，无需任何权限）

func systemIdleSeconds() -> Double {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iterator) == KERN_SUCCESS else { return 0 }
    defer { IOObjectRelease(iterator) }
    let entry = IOIteratorNext(iterator)
    guard entry != 0 else { return 0 }
    defer { IOObjectRelease(entry) }
    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dict = props?.takeRetainedValue() as? [String: Any],
          let idleNs = dict["HIDIdleTime"] as? Int64 else { return 0 }
    return Double(idleNs) / 1_000_000_000
}

// MARK: - 工具

func fmtDuration(_ seconds: TimeInterval) -> String {
    let s = Int(seconds)
    let h = s / 3600, m = (s % 3600) / 60
    if h > 0 { return "\(h) 小时 \(m) 分" }
    return "\(m) 分钟"
}

func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}

// 健康小贴士
let standTips = [
    "试试「20-20-20」护眼法则：看向 6 米外的地方，持续 20 秒。",
    "双手交叉向上举过头顶，深呼吸三次，伸展一下肩颈。",
    "去接杯水顺便走两步 —— 久坐一小时，下肢血液循环会明显变慢。",
    "靠墙站 1 分钟，后脑、肩胛、臀部贴墙，让脊柱回归中立位。",
    "踮踮脚、转转脚踝，各做 20 次，缓解腿部酸胀。"
]
let waterTips = [
    "小口慢饮比大口猛灌更解渴。",
    "温水最佳，一次 150~200 毫升就好。",
    "顺手看看窗外，让眼睛也休息 20 秒。"
]

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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "figure.seated.side")
                    .font(.title2)
                    .foregroundStyle(.teal)
                Text("使用统计")
                    .font(.title2).bold()
                Spacer()
            }

            Text("近 7 天累计使用时长")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Chart(days) { d in
                BarMark(
                    x: .value("日期", d.label),
                    y: .value("分钟", d.minutes)
                )
                .foregroundStyle(d.isToday ? Color.orange.gradient : Color.teal.gradient)
                .cornerRadius(4)
            }
            .chartYAxisLabel("分钟")
            .frame(height: 180)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("今日").font(.headline)
                statRow("累计使用", fmtDuration(today.totalActiveSeconds))
                statRow("当前连续", currentContinuous > 0 ? fmtDuration(currentContinuous) : "休息中")
                statRow("连续使用段", "\(today.sessions.count) 段")
                statRow("最长一段", fmtDuration(today.longestSessionSeconds))
                statRow("喝水 / 站立提醒", "\(today.waterReminders) / \(today.standReminders) 次")
                statRow("已完成休息", "\(today.breaks) 次")
            }
        }
        .padding(20)
        .frame(width: 400)
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

// MARK: - App

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let debugMode = CommandLine.arguments.contains("--debug")
    let testAlertMode = CommandLine.arguments.contains("--test-alert")
    let showStatsMode = CommandLine.arguments.contains("--show-stats")

    var statusItem: NSStatusItem!
    var config = Config()
    var stats = StatsStore()
    var configModDate: Date?
    var statsWindow: NSWindow?

    var sessionStart: Date?
    var lastPoll = Date()
    var lastWaterAlert: Date?
    var lastStandAlert: Date?
    var alertShowing = false
    var lastFlush = Date()

    // 数据目录：
    // - 安装在「应用程序」里运行时 → ~/Library/Application Support/UsageReminder/
    // - 开发调试（在别的目录运行）→ .app 旁边，方便查看
    lazy var baseDir: URL = {
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var dir = exe.deletingLastPathComponent()
        var isInstalled = false
        if dir.lastPathComponent == "MacOS",
           dir.deletingLastPathComponent().lastPathComponent == "Contents" {
            let bundle = dir.deletingLastPathComponent().deletingLastPathComponent()
            if bundle.pathExtension == "app" {
                let parent = bundle.deletingLastPathComponent()
                isInstalled = parent.path == "/Applications" || parent.path == NSHomeDirectory() + "/Applications"
                dir = parent
            }
        }
        if isInstalled {
            let support = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/UsageReminder")
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            return support
        }
        return dir
    }()
    lazy var configURL: URL = baseDir.appendingPathComponent("config.json")
    lazy var dataDir: URL = baseDir.appendingPathComponent("data")
    lazy var statsURL: URL = dataDir.appendingPathComponent("stats.json")

    let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    let weekdayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEE"
        return f
    }()

    func todayKey() -> String { dayFmt.string(from: Date()) }

    func today() -> DayStats { stats.days[todayKey()] ?? DayStats() }

    // MARK: 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        loadConfig()
        loadStats()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        updateStatusTitle(Date())
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.poll() }

        if testAlertMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.showAlert(title: "测试提醒 🧪", message: "强提醒工作正常：这个弹窗必须手动点掉。")
            }
        }
        if showStatsMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.openStatsWindow()
            }
        }
        log("started, baseDir=\(baseDir.path)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveStats()
    }

    // MARK: 主循环（每 5 秒）

    func poll() {
        let now = Date()
        let idle = systemIdleSeconds()
        let breakSecs = TimeInterval(config.breakResetMinutes * 60)
        let elapsed = now.timeIntervalSince(lastPoll)
        lastPoll = now

        if idle < breakSecs {
            // 使用中（或短暂停顿，仍算连续）
            if sessionStart == nil {
                sessionStart = now.addingTimeInterval(-idle)
                lastWaterAlert = nil
                lastStandAlert = nil
            }
            var d = today()
            d.totalActiveSeconds += elapsed
            stats.days[todayKey()] = d
            checkReminders(now: now)
        } else {
            // 已离开电脑，结束当前连续使用段
            if let s = sessionStart {
                endSession(start: s, end: now.addingTimeInterval(-idle))
            }
            sessionStart = nil
        }

        updateStatusTitle(now)
        reloadConfigIfChanged()

        // 每分钟落盘一次，防止意外退出丢数据
        if now.timeIntervalSince(lastFlush) > 60 {
            saveStats()
            lastFlush = now
        }
        if debugMode {
            log("idle=\(Int(idle))s continuous=\(sessionStart.map { Int(now.timeIntervalSince($0)) } ?? -1)s total=\(Int(today().totalActiveSeconds))s")
        }
    }

    func endSession(start: Date, end: Date) {
        let secs = end.timeIntervalSince(start)
        guard secs > 0 else { return }
        var d = today()
        d.sessions.append(Session(start: start.timeIntervalSince1970, end: end.timeIntervalSince1970, seconds: secs))
        d.longestSessionSeconds = max(d.longestSessionSeconds, secs)
        d.breaks += 1
        stats.days[todayKey()] = d
        saveStats()
        log("session ended: \(Int(secs))s")
    }

    // MARK: 提醒

    func checkReminders(now: Date) {
        guard !config.paused, let s = sessionStart else { return }
        let cont = now.timeIntervalSince(s)
        let repeatSecs = TimeInterval(config.repeatReminderMinutes * 60)

        func due(_ last: Date?, _ thresholdMinutes: Int) -> Bool {
            guard thresholdMinutes > 0 else { return false }  // 0 = 已关闭
            guard cont >= TimeInterval(thresholdMinutes * 60) else { return false }
            guard let last = last else { return true }
            return now.timeIntervalSince(last) >= repeatSecs
        }

        if due(lastStandAlert, config.standReminderMinutes) {
            lastStandAlert = now
            lastWaterAlert = now   // 避免两种提醒连着弹
            var d = today(); d.standReminders += 1; stats.days[todayKey()] = d; saveStats()
            let tip = standTips.randomElement() ?? ""
            showAlert(title: "该起来活动了 🧍",
                      message: "你已连续使用电脑 \(Int(cont / 60)) 分钟。\n\n\(tip)\n\n休息 \(config.breakResetMinutes) 分钟后计时才会重置。",
                      onSnooze: { [weak self] in self?.config.standReminderMinutes = 0; self?.saveConfig() })
        } else if due(lastWaterAlert, config.waterReminderMinutes) {
            lastWaterAlert = now
            var d = today(); d.waterReminders += 1; stats.days[todayKey()] = d; saveStats()
            let tip = waterTips.randomElement() ?? ""
            showAlert(title: "喝口水吧 💧",
                      message: "你已连续使用电脑 \(Int(cont / 60)) 分钟，补充点水分。\n\n\(tip)",
                      onSnooze: { [weak self] in self?.config.waterReminderMinutes = 0; self?.saveConfig() })
        }
    }

    // 强提醒弹窗：「知道了」点掉；「不再提醒」直接关闭该类型提醒
    func showAlert(title: String, message: String, onSnooze: (() -> Void)? = nil) {
        guard !alertShowing else { return }
        alertShowing = true
        NSSound.beep()
        let script = "display alert \"\(esc(title))\" message \"\(esc(message))\" buttons {\"知道了\", \"不再提醒\"} default button 1"
        DispatchQueue.global().async {
            let p = Process()
            let pipe = Pipe()
            p.launchPath = "/usr/bin/osascript"
            p.arguments = ["-e", script]
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            p.launch()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            p.waitUntilExit()
            self.alertShowing = false
            if out.contains("不再提醒") {
                DispatchQueue.main.async { onSnooze?() }
            }
        }
    }

    // MARK: 菜单栏图标 + 标题（SF Symbols 单色模板图标，自动适配深浅色）

    func updateStatusTitle(_ now: Date) {
        guard let button = statusItem.button else { return }
        let symbol: String
        let text: String
        if config.paused {
            symbol = "pause.circle"
            text = sessionStart.map { " \(Int(now.timeIntervalSince($0) / 60))分" } ?? ""
        } else if let s = sessionStart {
            symbol = "figure.seated.side"
            text = " \(Int(now.timeIntervalSince(s) / 60))分"
        } else {
            symbol = "cup.and.saucer"
            text = ""
        }
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "久坐提醒") {
            img.isTemplate = true   // 单色渲染，跟随系统菜单栏风格
            button.image = img
        }
        button.title = text
        button.imagePosition = .imageLeft
    }

    // MARK: 菜单（每次打开时重建，顺便刷新看板数据）

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = Date()
        let d = today()

        // 当前状态 + 下次提醒倒计时
        if let s = sessionStart {
            let cont = now.timeIntervalSince(s)
            menu.addItem(infoItem("已连续使用 \(fmtDuration(cont))"))
            if !config.paused, let next = nextReminder(now: now, cont: cont) {
                menu.addItem(infoItem(next))
            }
        } else {
            menu.addItem(infoItem("当前休息中 ☕️"))
        }
        menu.addItem(.separator())

        // 今日看板
        let header = NSMenuItem(title: "—— 今日看板 ——", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(infoItem("累计使用：\(fmtDuration(d.totalActiveSeconds))"))
        let longest = d.longestSessionSeconds
        let longestText = longest > 0 ? "（最长 \(fmtDuration(longest))）" : ""
        menu.addItem(infoItem("连续使用：\(d.sessions.count) 段\(longestText)"))
        menu.addItem(infoItem("喝水提醒 \(d.waterReminders) 次 · 站立提醒 \(d.standReminders) 次"))
        menu.addItem(infoItem("已完成休息：\(d.breaks) 次"))

        let detailItem = NSMenuItem(title: "统计详情…", action: #selector(openStats), keyEquivalent: "")
        detailItem.target = self
        menu.addItem(detailItem)

        // 近 7 天
        let weekItem = NSMenuItem(title: "近 7 天", action: nil, keyEquivalent: "")
        let weekSub = NSMenu()
        for line in last7DaysLines() {
            weekSub.addItem(infoItem(line))
        }
        weekItem.submenu = weekSub
        menu.addItem(weekItem)
        menu.addItem(.separator())

        // 暂停 / 恢复
        let pauseItem = NSMenuItem(title: config.paused ? "恢复提醒" : "暂停提醒",
                                   action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)

        // 提醒设置
        let settings = NSMenuItem(title: "提醒设置", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        addOptionGroup(to: sub, title: "喝水提醒", options: [30, 45, 60, 90],
                       current: config.waterReminderMinutes, action: #selector(setWater(_:)), allowOff: true)
        sub.addItem(.separator())
        addOptionGroup(to: sub, title: "站立提醒", options: [45, 60, 75, 90],
                       current: config.standReminderMinutes, action: #selector(setStand(_:)), allowOff: true)
        sub.addItem(.separator())
        addOptionGroup(to: sub, title: "重复提醒间隔", options: [10, 15, 20, 30],
                       current: config.repeatReminderMinutes, action: #selector(setRepeat(_:)))
        sub.addItem(.separator())
        addOptionGroup(to: sub, title: "休息判定（无操作多久算休息）", options: [3, 5, 8, 10],
                       current: config.breakResetMinutes, action: #selector(setBreak(_:)))
        settings.submenu = sub
        menu.addItem(settings)
        menu.addItem(.separator())

        // 开机自启动
        let loginItem = NSMenuItem(title: "开机自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        let openItem = NSMenuItem(title: "打开数据文件夹", action: #selector(openDataFolder), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // 下一个提醒的倒计时文案
    func nextReminder(now: Date, cont: TimeInterval) -> String? {
        let contMin = cont / 60
        var candidates: [(String, Double)] = []
        if config.waterReminderMinutes > 0 { candidates.append(("喝水", Double(config.waterReminderMinutes))) }
        if config.standReminderMinutes > 0 { candidates.append(("站立", Double(config.standReminderMinutes))) }
        guard let next = candidates.sorted(by: { $0.1 < $1.1 }).first else { return nil }
        if contMin < next.1 {
            return "距\(next.0)提醒还有 \(Int(next.1 - contMin)) 分钟"
        }
        return nil
    }

    func last7DaysLines() -> [String] {
        var lines: [String] = []
        let cal = Calendar.current
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let key = dayFmt.string(from: date)
            let weekday = weekdayFmt.string(from: date)
            let day = stats.days[key]
            let label = offset == 0 ? "今天" : weekday
            if let day = day, day.totalActiveSeconds > 0 {
                lines.append("\(label)：\(fmtDuration(day.totalActiveSeconds)) · 休息 \(day.breaks) 次")
            } else {
                lines.append("\(label)：无记录")
            }
        }
        return lines
    }

    func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: "   \(title)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    func addOptionGroup(to menu: NSMenu, title: String, options: [Int], current: Int, action: Selector, allowOff: Bool = false) {
        let header = NSMenuItem(title: "   \(title)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if allowOff {
            let off = NSMenuItem(title: "关闭", action: action, keyEquivalent: "")
            off.target = self
            off.tag = 0
            off.state = (current == 0) ? .on : .off
            menu.addItem(off)
        }
        for opt in options {
            let item = NSMenuItem(title: "\(opt) 分钟", action: action, keyEquivalent: "")
            item.target = self
            item.tag = opt
            item.state = (opt == current) ? .on : .off
            menu.addItem(item)
        }
    }

    // MARK: 菜单动作

    @objc func togglePause() {
        config.paused.toggle()
        saveConfig()
        updateStatusTitle(Date())
    }

    @objc func setWater(_ sender: NSMenuItem) { config.waterReminderMinutes = sender.tag; saveConfig() }
    @objc func setStand(_ sender: NSMenuItem) { config.standReminderMinutes = sender.tag; saveConfig() }
    @objc func setRepeat(_ sender: NSMenuItem) { config.repeatReminderMinutes = sender.tag; saveConfig() }
    @objc func setBreak(_ sender: NSMenuItem) { config.breakResetMinutes = sender.tag; saveConfig() }

    @objc func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert(title: "设置失败",
                      message: "无法自动设置开机启动。\n请手动前往：系统设置 → 通用 → 登录项与扩展 → 添加「久坐提醒」。")
        }
    }

    @objc func openStats() {
        openStatsWindow()
    }

    func openStatsWindow() {
        let now = Date()
        let cal = Calendar.current
        var bars: [DayBar] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let date = cal.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = dayFmt.string(from: date)
            let day = stats.days[key]
            let label = offset == 0 ? "今天" : weekdayFmt.string(from: date)
            bars.append(DayBar(label: label,
                               minutes: (day?.totalActiveSeconds ?? 0) / 60,
                               isToday: offset == 0))
        }
        let cont = sessionStart.map { now.timeIntervalSince($0) } ?? 0
        let view = StatsView(days: bars, today: today(), currentContinuous: cont)

        let win = NSWindow(contentViewController: NSHostingController(rootView: view))
        win.title = "久坐提醒 · 使用统计"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        statsWindow = win
    }

    @objc func openDataFolder() {
        NSWorkspace.shared.open(baseDir)
    }

    @objc func quit() {
        saveStats()
        NSApplication.shared.terminate(nil)
    }

    // MARK: 配置 / 数据读写

    func loadConfig() {
        guard let data = try? Data(contentsOf: configURL),
              let c = try? JSONDecoder().decode(Config.self, from: data) else {
            saveConfig() // 首次运行，写入默认配置
            return
        }
        config = c
        configModDate = try? configURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    func reloadConfigIfChanged() {
        guard let mod = try? configURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return }
        if configModDate == nil || mod > configModDate! {
            configModDate = mod
            loadConfig()
            log("config reloaded")
        }
    }

    func saveConfig() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
        configModDate = try? configURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    func loadStats() {
        guard let data = try? Data(contentsOf: statsURL),
              let s = try? JSONDecoder().decode(StatsStore.self, from: data) else { return }
        stats = s
    }

    func saveStats() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(stats) else { return }
        try? data.write(to: statsURL, options: .atomic)
    }

    func log(_ msg: String) {
        if debugMode { FileHandle.standardOutput.write("[\(Date())] \(msg)\n".data(using: .utf8)!) }
    }
}

// MARK: - 入口

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // 纯菜单栏应用，不出现在 Dock
let delegate = AppDelegate()
app.delegate = delegate
app.run()
