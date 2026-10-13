import Cocoa
import SwiftUI
import ServiceManagement

// MARK: - App

class AppDelegate: NSObject, NSApplicationDelegate {
    let debugMode = CommandLine.arguments.contains("--debug")
    let testAlertMode = CommandLine.arguments.contains("--test-alert")
    let showStatsMode = CommandLine.arguments.contains("--show-stats")
    let testDashboardMode = CommandLine.arguments.contains("--test-dashboard")
    let testSettingsMode = CommandLine.arguments.contains("--test-settings")

    var config = Config()
    var stats = StatsStore()
    var configModDate: Date?
    var statsWindow: NSWindow?
    let island = NotchIslandController()
    let settingsPanel = SettingsPanelController()

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

        // 灵动岛：左键看板，右键设置
        island.onRightClick = { [weak self] in self?.toggleSettings() }
        updateIsland(Date())
        island.start(enabled: config.islandEnabled)
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.poll() }

        if testAlertMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.showReminder(icon: "figure.stand",
                                  title: L.t("测试提醒 🧪", "Test alert 🧪"),
                                  message: L.t("提醒样式预览。点一下关闭。",
                                               "Reminder style preview. Tap to dismiss."),
                                  snoozeKey: nil)
            }
        }
        if showStatsMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.openStatsWindow()
            }
        }
        if testDashboardMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.island.toggleDashboard()
            }
        }
        if testSettingsMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.toggleSettings()
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
            if let s = sessionStart {
                endSession(start: s, end: now.addingTimeInterval(-idle))
            }
            sessionStart = nil
        }

        updateIsland(now)
        reloadConfigIfChanged()

        if now.timeIntervalSince(lastFlush) > 60 {
            saveStats()
            lastFlush = now
        }
        if debugMode {
            log("idle=\(Int(idle))s continuous=\(sessionStart.map { Int(now.timeIntervalSince($0)) } ?? -1)s total=\(Int(today().totalActiveSeconds))s quiet=\(inQuietHours(now))")
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

        // 久坐后成功休息 → 发个鼓励通知（不打断，自动消失）
        if secs >= 30 * 60, !config.paused, !inQuietHours(Date()) {
            showNotification(L.t("干得漂亮 🎉", "Well done 🎉"),
                             L.t("连续工作 \(fmtDuration(secs)) 后成功休息了一次，身体谢谢你。",
                                 "You took a real break after \(fmtDuration(secs)) of work. Your body thanks you."))
        }
    }

    // MARK: 提醒

    func inQuietHours(_ now: Date) -> Bool {
        let h = Calendar.current.component(.hour, from: now)
        for period in config.quietPeriods {
            guard period.count == 2 else { continue }
            let s = period[0], e = period[1]
            let inside = s <= e ? (h >= s && h < e) : (h >= s || h < e)  // 支持跨午夜
            if inside { return true }
        }
        return false
    }

    func checkReminders(now: Date) {
        guard !config.paused, !inQuietHours(now), let s = sessionStart else { return }
        let cont = now.timeIntervalSince(s)
        let repeatSecs = TimeInterval(config.repeatReminderMinutes * 60)

        func due(_ last: Date?, _ thresholdMinutes: Int) -> Bool {
            guard thresholdMinutes > 0 else { return false }
            guard cont >= TimeInterval(thresholdMinutes * 60) else { return false }
            guard let last = last else { return true }
            return now.timeIntervalSince(last) >= repeatSecs
        }

        if due(lastStandAlert, config.standReminderMinutes) {
            lastStandAlert = now
            lastWaterAlert = now
            var d = today(); d.standReminders += 1; stats.days[todayKey()] = d; saveStats()
            let tip = L.isZh ? (standTipsZh.randomElement() ?? "") : (standTipsEn.randomElement() ?? "")
            let mins = Int(cont / 60)
            showReminder(icon: "figure.stand",
                         title: L.t("该起来活动了 🧍", "Time to stand up 🧍"),
                         message: L.t("已连续使用 \(mins) 分钟。\(tip)",
                                      "\(mins) minutes straight. \(tip)"),
                         snoozeKey: "stand")
        } else if due(lastWaterAlert, config.waterReminderMinutes) {
            lastWaterAlert = now
            var d = today(); d.waterReminders += 1; stats.days[todayKey()] = d; saveStats()
            let tip = L.isZh ? (waterTipsZh.randomElement() ?? "") : (waterTipsEn.randomElement() ?? "")
            let mins = Int(cont / 60)
            showReminder(icon: "drop.fill",
                         title: L.t("喝口水吧 💧", "Drink some water 💧"),
                         message: L.t("已连续使用 \(mins) 分钟。\(tip)",
                                      "\(mins) minutes straight. \(tip)"),
                         snoozeKey: "water")
        }
    }

    // 提醒分发：灵动岛胶囊（默认）/ 弹窗强提醒 / 普通通知
    func showReminder(icon: String, title: String, message: String, snoozeKey: String?) {
        NSSound.beep()
        switch config.reminderStyle {
        case .notch:
            island.showReminder(icon: icon, title: title, message: message) { /* 点按即确认 */ }
        case .gentle:
            showNotification(title, message)
        case .strong:
            showStrongAlert(title: title, message: message, snoozeKey: snoozeKey)
        }
    }

    // 温和通知（自动消失，不打断）
    func showNotification(_ title: String, _ message: String) {
        let script = "display notification \"\(esc(message))\" with title \"\(esc(title))\" sound name \"Glass\""
        DispatchQueue.global().async {
            let p = Process()
            p.launchPath = "/usr/bin/osascript"
            p.arguments = ["-e", script]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.launch()
        }
    }

    // 强提醒弹窗：「知道了」点掉；「不再提醒」直接关闭该类型提醒
    func showStrongAlert(title: String, message: String, snoozeKey: String?) {
        guard !alertShowing else { return }
        alertShowing = true
        let okBtn = L.t("知道了", "Got it")
        let offBtn = L.t("不再提醒", "Don't remind me")
        let script = "display alert \"\(esc(title))\" message \"\(esc(message))\" buttons {\"\(okBtn)\", \"\(offBtn)\"} default button 1"
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
            if out.contains(offBtn), let key = snoozeKey {
                DispatchQueue.main.async { self.snoozeReminder(key) }
            }
        }
    }

    func snoozeReminder(_ key: String) {
        if key == "water" { config.waterReminderMinutes = 0 }
        if key == "stand" { config.standReminderMinutes = 0 }
        saveConfig()
    }

    // MARK: 灵动岛状态刷新

    // 把当前状态喂给常驻灵动岛
    func updateIsland(_ now: Date) {
        let unit = L.t("分", "m")
        let d = today()
        var icon = "cup.and.saucer"
        var text = ""
        var tint = Color.white
        var line1 = L.t("当前休息中 ☕️", "Resting ☕️")

        if let s = sessionStart {
            let cont = now.timeIntervalSince(s)
            let mins = Int(cont / 60)
            icon = "figure.seated.side"
            text = " \(mins)\(unit)"
            line1 = L.t("已连续使用 \(fmtDuration(cont))", "Active for \(fmtDuration(cont))")
            if config.paused {
                icon = "pause.circle"
                tint = Color(white: 0.55)
                line1 = L.t("已暂停提醒 ⏸", "Reminders paused ⏸")
            }
        }

        let line2 = L.t("今日累计 \(fmtDuration(d.totalActiveSeconds)) · 休息 \(d.breaks) 次",
                        "Today \(fmtDuration(d.totalActiveSeconds)) · \(d.breaks) breaks")
        var line3 = ""
        if inQuietHours(now) {
            line3 = L.t("免打扰中 🌙", "Quiet hours 🌙")
        } else if config.paused {
            line3 = L.t("提醒已暂停", "Reminders paused")
        } else if let s = sessionStart, let next = nextReminder(now: now, cont: now.timeIntervalSince(s)) {
            line3 = next
        } else {
            line3 = L.t("暂无待提醒事项", "No pending reminders")
        }
        if sessionStart == nil { icon = "cup.and.saucer"; tint = Color(white: 0.9); text = "" }

        island.update(icon: icon, text: text, tint: tint,
                      line1: line1, line2: line2, line3: line3)
    }

    // MARK: 设置面板（右键灵动岛打开）

    func toggleSettings() {
        settingsPanel.toggle { [weak self] m in
            guard let self = self else { return }
            m.paused = self.config.paused
            m.launchAtLogin = SMAppService.mainApp.status == .enabled
            m.islandEnabled = self.config.islandEnabled
            m.waterMinutes = self.config.waterReminderMinutes
            m.standMinutes = self.config.standReminderMinutes
            m.repeatMinutes = self.config.repeatReminderMinutes
            m.breakMinutes = self.config.breakResetMinutes
            m.quietPeriods = self.config.quietPeriods
            m.reminderStyle = self.config.reminderStyle
            m.onChanged = { self.applySettings(m) }
            m.onStylePreview = { self.previewReminderStyle() }
            m.onOpenStats = { self.openStatsWindow() }
            m.onOpenDataFolder = { NSWorkspace.shared.open(self.baseDir) }
            m.onQuit = { self.quitApp() }
        }
    }

    // 设置面板任何字段变化都落到这里
    func applySettings(_ m: SettingsModel) {
        config.paused = m.paused
        config.islandEnabled = m.islandEnabled
        config.waterReminderMinutes = m.waterMinutes
        config.standReminderMinutes = m.standMinutes
        config.repeatReminderMinutes = m.repeatMinutes
        config.breakResetMinutes = m.breakMinutes
        config.quietPeriods = m.quietPeriods
        config.reminderStyle = m.reminderStyle
        saveConfig()

        island.start(enabled: config.islandEnabled)
        applyLaunchAtLogin(m.launchAtLogin)
        updateIsland(Date())
    }

    func previewReminderStyle() {
        showReminder(icon: "sparkles",
                     title: L.t("提醒方式已切换", "Reminder style updated"),
                     message: L.t("以后提醒会长这样。点一下关闭。", "Future reminders will look like this. Tap to dismiss."),
                     snoozeKey: nil)
    }

    func applyLaunchAtLogin(_ enable: Bool) {
        do {
            if enable && SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !enable && SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            showStrongAlert(title: L.t("设置失败", "Setup failed"),
                            message: L.t("无法自动设置开机启动。\n请手动前往：系统设置 → 通用 → 登录项与扩展 → 添加「久坐提醒」。",
                                         "Couldn't set launch-at-login automatically.\nPlease go to System Settings → General → Login Items and add UsageReminder manually."),
                            snoozeKey: nil)
        }
    }

    // 下一个提醒的倒计时文案
    func nextReminder(now: Date, cont: TimeInterval) -> String? {
        let contMin = cont / 60
        var candidates: [(String, Double)] = []
        if config.waterReminderMinutes > 0 { candidates.append((L.t("喝水", "water"), Double(config.waterReminderMinutes))) }
        if config.standReminderMinutes > 0 { candidates.append((L.t("站立", "stand"), Double(config.standReminderMinutes))) }
        guard let next = candidates.sorted(by: { $0.1 < $1.1 }).first else { return nil }
        if contMin < next.1 {
            let left = Int(next.1 - contMin)
            return L.t("距\(next.0)提醒还有 \(left) 分钟", "\(next.0.capitalized) reminder in \(left)m")
        }
        return nil
    }

    @objc func openStats() {
        openStatsWindow()
    }

    func openStatsWindow() {
        log("openStatsWindow called")
        let now = Date()
        let cal = Calendar.current
        var bars: [DayBar] = []
        var weekTotal: TimeInterval = 0
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let date = cal.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = dayFmt.string(from: date)
            let day = stats.days[key]
            let label = offset == 0 ? L.t("今天", "Today") : weekdayFmt.string(from: date)
            let secs = day?.totalActiveSeconds ?? 0
            weekTotal += secs
            bars.append(DayBar(label: label, minutes: secs / 60, isToday: offset == 0))
        }
        let cont = sessionStart.map { now.timeIntervalSince($0) } ?? 0
        let view = StatsView(days: bars, today: today(), currentContinuous: cont, weekTotal: weekTotal)

        let win = NSWindow(contentViewController: NSHostingController(rootView: view))
        win.title = L.t("久坐提醒 · 使用统计", "UsageReminder · Stats")
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 440, height: 620))  // 显式尺寸，避免 hosting 布局塌缩
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()   // 确保窗口在其他应用之上
        NSApp.activate(ignoringOtherApps: true)
        statsWindow = win
        log("stats window visible=\(win.isVisible) frame=\(win.frame)")
    }

    @objc func openDataFolder() {
        NSWorkspace.shared.open(baseDir)
    }

    @objc func quit() {
        quitApp()
    }

    func quitApp() {
        saveStats()
        NSApplication.shared.terminate(nil)
    }

    // MARK: 配置 / 数据读写

    func loadConfig() {
        guard let data = try? Data(contentsOf: configURL),
              let c = try? JSONDecoder().decode(Config.self, from: data) else {
            saveConfig()
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
