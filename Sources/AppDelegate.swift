import Cocoa
import SwiftUI
import ServiceManagement

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
                self.showAlert(title: L.t("测试提醒 🧪", "Test alert 🧪"),
                               message: L.t("强提醒工作正常：这个弹窗必须手动点掉。",
                                            "Strong alerts work: this dialog must be dismissed manually."))
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

        updateStatusTitle(now)
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
        let s = config.quietHoursStart, e = config.quietHoursEnd
        guard s >= 0, e >= 0 else { return false }
        let h = Calendar.current.component(.hour, from: now)
        return s <= e ? (h >= s && h < e) : (h >= s || h < e)  // 支持跨午夜区间
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
            showAlert(title: L.t("该起来活动了 🧍", "Time to stand up 🧍"),
                      message: L.t("你已连续使用电脑 \(mins) 分钟。\n\n\(tip)\n\n休息 \(config.breakResetMinutes) 分钟后计时才会重置。",
                                   "You've been using your Mac for \(mins) minutes straight.\n\n\(tip)\n\nThe timer resets after a \(config.breakResetMinutes)-minute break."),
                      onSnooze: { [weak self] in self?.config.standReminderMinutes = 0; self?.saveConfig() })
        } else if due(lastWaterAlert, config.waterReminderMinutes) {
            lastWaterAlert = now
            var d = today(); d.waterReminders += 1; stats.days[todayKey()] = d; saveStats()
            let tip = L.isZh ? (waterTipsZh.randomElement() ?? "") : (waterTipsEn.randomElement() ?? "")
            let mins = Int(cont / 60)
            showAlert(title: L.t("喝口水吧 💧", "Drink some water 💧"),
                      message: L.t("你已连续使用电脑 \(mins) 分钟，补充点水分。\n\n\(tip)",
                                   "You've been using your Mac for \(mins) minutes. Hydrate!\n\n\(tip)"),
                      onSnooze: { [weak self] in self?.config.waterReminderMinutes = 0; self?.saveConfig() })
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

    // 提醒：温和模式用系统通知（自动消失），否则强提醒弹窗（必须手动点掉）
    func showAlert(title: String, message: String, onSnooze: (() -> Void)? = nil) {
        if config.gentleMode {
            showNotification(title, message)
            return
        }
        guard !alertShowing else { return }
        alertShowing = true
        NSSound.beep()
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
            if out.contains(offBtn) {
                DispatchQueue.main.async { onSnooze?() }
            }
        }
    }

    // MARK: 菜单栏图标 + 标题（SF Symbols 单色模板图标，自动适配深浅色）

    func updateStatusTitle(_ now: Date) {
        guard let button = statusItem.button else { return }
        let unit = L.t("分", "m")
        let symbol: String
        let text: String
        if config.paused {
            symbol = "pause.circle"
            text = sessionStart.map { " \(Int(now.timeIntervalSince($0) / 60))\(unit)" } ?? ""
        } else if let s = sessionStart {
            symbol = "figure.seated.side"
            text = " \(Int(now.timeIntervalSince(s) / 60))\(unit)"
        } else {
            symbol = "cup.and.saucer"
            text = ""
        }
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "UsageReminder") {
            img.isTemplate = true
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
            menu.addItem(infoItem(L.t("已连续使用 \(fmtDuration(cont))", "Active for \(fmtDuration(cont))")))
            if !config.paused, let next = nextReminder(now: now, cont: cont) {
                menu.addItem(infoItem(next))
            }
            if inQuietHours(now) {
                menu.addItem(infoItem(L.t("免打扰中 🌙", "Quiet hours 🌙")))
            }
        } else {
            menu.addItem(infoItem(L.t("当前休息中 ☕️", "Resting ☕️")))
        }
        menu.addItem(.separator())

        // 今日看板
        let header = NSMenuItem(title: L.t("—— 今日看板 ——", "—— Today ——"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(infoItem(L.t("累计使用：\(fmtDuration(d.totalActiveSeconds))", "Total: \(fmtDuration(d.totalActiveSeconds))")))
        let longest = d.longestSessionSeconds
        let longestTextZh = longest > 0 ? "（最长 \(fmtDuration(longest))）" : ""
        let longestTextEn = longest > 0 ? " (longest \(fmtDuration(longest)))" : ""
        menu.addItem(infoItem(L.t("连续使用：\(d.sessions.count) 段\(longestTextZh)",
                                  "Sessions: \(d.sessions.count)\(longestTextEn)")))
        menu.addItem(infoItem(L.t("喝水提醒 \(d.waterReminders) 次 · 站立提醒 \(d.standReminders) 次",
                                  "Water ×\(d.waterReminders) · Stand ×\(d.standReminders)")))
        menu.addItem(infoItem(L.t("已完成休息：\(d.breaks) 次", "Breaks taken: \(d.breaks)")))

        let detailItem = NSMenuItem(title: L.t("统计详情…", "View Stats…"), action: #selector(openStats), keyEquivalent: "")
        detailItem.target = self
        menu.addItem(detailItem)

        // 近 7 天
        let weekItem = NSMenuItem(title: L.t("近 7 天", "Last 7 Days"), action: nil, keyEquivalent: "")
        let weekSub = NSMenu()
        for line in last7DaysLines() {
            weekSub.addItem(infoItem(line))
        }
        weekItem.submenu = weekSub
        menu.addItem(weekItem)
        menu.addItem(.separator())

        // 暂停 / 恢复
        let pauseItem = NSMenuItem(title: L.t(config.paused ? "恢复提醒" : "暂停提醒",
                                              config.paused ? "Resume Reminders" : "Pause Reminders"),
                                   action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)

        // 提醒设置
        let settings = NSMenuItem(title: L.t("提醒设置", "Reminder Settings"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        addOptionGroup(to: sub, title: L.t("喝水提醒", "Water reminder"), options: [30, 45, 60, 90],
                       current: config.waterReminderMinutes, action: #selector(setWater(_:)), allowOff: true)
        sub.addItem(.separator())
        addOptionGroup(to: sub, title: L.t("站立提醒", "Stand reminder"), options: [45, 60, 75, 90],
                       current: config.standReminderMinutes, action: #selector(setStand(_:)), allowOff: true)
        sub.addItem(.separator())
        addOptionGroup(to: sub, title: L.t("重复提醒间隔", "Repeat every"), options: [10, 15, 20, 30],
                       current: config.repeatReminderMinutes, action: #selector(setRepeat(_:)))
        sub.addItem(.separator())
        addOptionGroup(to: sub, title: L.t("休息判定（无操作多久算休息）", "Break threshold (idle time)"), options: [3, 5, 8, 10],
                       current: config.breakResetMinutes, action: #selector(setBreak(_:)))
        sub.addItem(.separator())
        addQuietHoursGroup(to: sub)
        sub.addItem(.separator())
        let gentleItem = NSMenuItem(title: L.t("温和提醒（通知不挡屏幕）", "Gentle mode (banner notifications)"),
                                    action: #selector(toggleGentle), keyEquivalent: "")
        gentleItem.target = self
        gentleItem.state = config.gentleMode ? .on : .off
        sub.addItem(gentleItem)
        settings.submenu = sub
        menu.addItem(settings)
        menu.addItem(.separator())

        // 开机自启动
        let loginItem = NSMenuItem(title: L.t("开机自动启动", "Launch at Login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        let openItem = NSMenuItem(title: L.t("打开数据文件夹", "Open Data Folder"), action: #selector(openDataFolder), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let quitItem = NSMenuItem(title: L.t("退出", "Quit"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // 免打扰时段预设：tag 0=关闭 1=午休 2=夜间
    func addQuietHoursGroup(to menu: NSMenu) {
        let header = NSMenuItem(title: L.t("   免打扰时段", "   Quiet hours"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let current: Int
        if config.quietHoursStart == 12 && config.quietHoursEnd == 14 { current = 1 }
        else if config.quietHoursStart == 22 && config.quietHoursEnd == 8 { current = 2 }
        else { current = 0 }
        let presets: [(Int, String, String)] = [
            (0, "关闭", "Off"),
            (1, "午休 12:00–14:00", "Lunch 12:00–14:00"),
            (2, "夜间 22:00–08:00", "Night 22:00–08:00")
        ]
        for (tag, zh, en) in presets {
            let item = NSMenuItem(title: L.t(zh, en), action: #selector(setQuiet(_:)), keyEquivalent: "")
            item.target = self
            item.tag = tag
            item.state = (tag == current) ? .on : .off
            menu.addItem(item)
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

    func last7DaysLines() -> [String] {
        var lines: [String] = []
        let cal = Calendar.current
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let key = dayFmt.string(from: date)
            let weekday = weekdayFmt.string(from: date)
            let day = stats.days[key]
            let label = offset == 0 ? L.t("今天", "Today") : weekday
            if let day = day, day.totalActiveSeconds > 0 {
                lines.append(L.t("\(label)：\(fmtDuration(day.totalActiveSeconds)) · 休息 \(day.breaks) 次",
                                 "\(label): \(fmtDuration(day.totalActiveSeconds)) · \(day.breaks) breaks"))
            } else {
                lines.append(L.t("\(label)：无记录", "\(label): no data"))
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
            let off = NSMenuItem(title: L.t("关闭", "Off"), action: action, keyEquivalent: "")
            off.target = self
            off.tag = 0
            off.state = (current == 0) ? .on : .off
            menu.addItem(off)
        }
        for opt in options {
            let item = NSMenuItem(title: L.t("\(opt) 分钟", "\(opt) min"), action: action, keyEquivalent: "")
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

    @objc func toggleGentle() {
        config.gentleMode.toggle()
        saveConfig()
    }

    @objc func setWater(_ sender: NSMenuItem) { config.waterReminderMinutes = sender.tag; saveConfig() }
    @objc func setStand(_ sender: NSMenuItem) { config.standReminderMinutes = sender.tag; saveConfig() }
    @objc func setRepeat(_ sender: NSMenuItem) { config.repeatReminderMinutes = sender.tag; saveConfig() }
    @objc func setBreak(_ sender: NSMenuItem) { config.breakResetMinutes = sender.tag; saveConfig() }

    @objc func setQuiet(_ sender: NSMenuItem) {
        switch sender.tag {
        case 1: config.quietHoursStart = 12; config.quietHoursEnd = 14
        case 2: config.quietHoursStart = 22; config.quietHoursEnd = 8
        default: config.quietHoursStart = -1; config.quietHoursEnd = -1
        }
        saveConfig()
    }

    @objc func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert(title: L.t("设置失败", "Setup failed"),
                      message: L.t("无法自动设置开机启动。\n请手动前往：系统设置 → 通用 → 登录项与扩展 → 添加「久坐提醒」。",
                                   "Couldn't set launch-at-login automatically.\nPlease go to System Settings → General → Login Items and add UsageReminder manually."))
        }
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
