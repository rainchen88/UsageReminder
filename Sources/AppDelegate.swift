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
    let island = NotchIslandController()
    let controlCenter = ControlCenterController()

    var sessionStart: Date?
    var lastPoll = Date()
    var lastWaterAlert: Date?
    var lastStandAlert: Date?
    var alertShowing = false
    var lastFlush = Date()
    var fullscreenNow = false          // 前台 App 是否全屏（会议/视频自动免打扰）
    var waterEscalation = 0            // 喝水提醒连续被忽略次数
    var standEscalation = 0            // 站立提醒连续被忽略次数
    var termSignalSource: DispatchSourceSignal?   // 持有 SIGTERM 监听，防止被释放

    // 数据目录：统一放 ~/Library/Application Support/UsageReminder/
    // 不管 app 从哪里运行（应用程序 / 下载 / 桌面），数据都指向同一个家，更新绝不丢数据。
    // 只有带 --dev-data 旗标的调试运行才用可执行文件旁边的目录。
    lazy var baseDir: URL = {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/UsageReminder")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let exeDir = exe.deletingLastPathComponent()
        if CommandLine.arguments.contains("--dev-data") {
            return exeDir   // 开发调试
        }

        // 旧版本数据迁移：app 旁边有数据、统一目录里没有 → 搬过来
        var legacyDir = exeDir
        if exeDir.lastPathComponent == "MacOS",
           exeDir.deletingLastPathComponent().lastPathComponent == "Contents" {
            let bundle = exeDir.deletingLastPathComponent().deletingLastPathComponent()
            if bundle.pathExtension == "app" {
                legacyDir = bundle.deletingLastPathComponent()
            }
        }
        let fm = FileManager.default
        let legacyConfig = legacyDir.appendingPathComponent("config.json")
        let newConfig = support.appendingPathComponent("config.json")
        if !fm.fileExists(atPath: newConfig.path), fm.fileExists(atPath: legacyConfig.path) {
            try? fm.copyItem(at: legacyConfig, to: newConfig)
            let legacyData = legacyDir.appendingPathComponent("data")
            if fm.fileExists(atPath: legacyData.path) {
                try? fm.copyItem(at: legacyData, to: support.appendingPathComponent("data"))
            }
        }
        return support
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

        // 灵动岛：左键看板，右键控制台
        island.onRightClick = { [weak self] in self?.toggleSettings() }
        island.applyAppearance(width: CGFloat(config.islandWidth), expandedHeight: CGFloat(config.expandedHeight), earPadding: CGFloat(config.pillPadding))
        updateIsland(Date())
        island.start(enabled: config.islandEnabled)
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.poll() }

        // 优雅处理 SIGTERM（更新/覆盖安装前的 pkill）：先落盘再退出，最多不丢一秒
        signal(SIGTERM, SIG_IGN)
        let termSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSrc.setEventHandler { [weak self] in
            self?.saveStats()
            exit(0)
        }
        termSrc.resume()
        termSignalSource = termSrc

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
                let tabArg = CommandLine.arguments.first(where: { $0.hasPrefix("--test-tab=") })
                let tab = tabArg
                    .flatMap { Int($0.split(separator: "=")[1]) }
                    .flatMap { ControlTab(rawValue: $0) }
                self.controlCenter.show(actions: { self.wireControlCenter($0) }, tab: tab)
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
        fullscreenNow = config.fullscreenPause && isFrontmostFullscreen()

        if idle < breakSecs {
            if sessionStart == nil {
                // 重启/更新续接：stats 里存着上一段未结束的会话 → 接着算，不清零
                if let saved = stats.ongoingSessionStart, saved <= now.timeIntervalSince1970 {
                    sessionStart = Date(timeIntervalSince1970: saved)
                    log("session restored from disk: \(Int(now.timeIntervalSince(sessionStart!)))s")
                } else {
                    sessionStart = now.addingTimeInterval(-idle)
                }
                stats.ongoingSessionStart = sessionStart!.timeIntervalSince1970
                saveStats()
                lastWaterAlert = nil
                lastStandAlert = nil
            }
            stats.lastActiveAt = now.timeIntervalSince1970
            var d = today()
            d.totalActiveSeconds += elapsed
            stats.days[todayKey()] = d
            checkReminders(now: now)
        } else {
            if let s = sessionStart {
                endSession(start: s, end: now.addingTimeInterval(-idle))
            } else if let saved = stats.ongoingSessionStart {
                // 上次退出时还在用电脑，现在处于休息：按最后活跃时间把那段会话收尾
                let end = Date(timeIntervalSince1970: stats.lastActiveAt ?? saved)
                endSession(start: Date(timeIntervalSince1970: saved), end: max(end, Date(timeIntervalSince1970: saved)))
            }
            sessionStart = nil
        }

        updateIsland(now)
        checkWeeklyReport(now: now)
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
        stats.ongoingSessionStart = nil
        stats.lastActiveAt = nil
        guard secs > 0 else { saveStats(); return }
        var d = today()
        d.sessions.append(Session(start: start.timeIntervalSince1970, end: end.timeIntervalSince1970, seconds: secs))
        d.longestSessionSeconds = max(d.longestSessionSeconds, secs)
        d.breaks += 1
        stats.days[todayKey()] = d
        saveStats()
        log("session ended: \(Int(secs))s")

        // 久坐后成功休息 → 休息打卡（灵动岛 ✅ 卡片 / 其他模式走通知）
        waterEscalation = 0
        standEscalation = 0   // 真休息后提醒等级归零
        if secs >= 30 * 60, config.breakPraiseEnabled, !config.paused, !inQuietHours(Date()) {
            let breaksToday = today().breaks
            let msg = L.t("连续工作 \(fmtDuration(secs)) 后休息了一次，这是今日第 \(breaksToday) 次休息。",
                          "You took a real break after \(fmtDuration(secs)) — break #\(breaksToday) today.")
            if config.reminderStyle == .notch {
                island.showCelebration(title: L.t("休息完成 ✅", "Break complete ✅"), message: msg)
            } else {
                showNotification(L.t("干得漂亮 🎉", "Well done 🎉"), msg)
            }
        }
    }

    // 全屏检测：前台 App 的窗口铺满整块屏（开会/看视频）→ 自动免打扰
    func isFrontmostFullscreen() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let screen = NSScreen.main else { return false }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        for w in list {
            guard let owner = w[kCGWindowOwnerPID as String] as? Int32, owner == pid,
                  let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let wf = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                            width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            if wf.width >= screen.frame.width - 4 && wf.height >= screen.frame.height - 4 { return true }
        }
        return false
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
        guard !config.paused, !inQuietHours(now), !fullscreenNow, let s = sessionStart else { return }
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
            let c = reminderCopy(kind: "stand", mins: mins, tip: tip)
            showReminder(icon: "figure.stand",
                         title: c.title, message: c.message,
                         snoozeKey: "stand", level: standEscalation)
        } else if due(lastWaterAlert, config.waterReminderMinutes) {
            lastWaterAlert = now
            var d = today(); d.waterReminders += 1; stats.days[todayKey()] = d; saveStats()
            let tip = L.isZh ? (waterTipsZh.randomElement() ?? "") : (waterTipsEn.randomElement() ?? "")
            let mins = Int(cont / 60)
            let c = reminderCopy(kind: "water", mins: mins, tip: tip)
            showReminder(icon: "drop.fill",
                         title: c.title, message: c.message,
                         snoozeKey: "water", level: waterEscalation)
        }
    }

    func bumpEscalation(_ key: String?) {
        guard config.escalateReminders else { return }
        if key == "water" { waterEscalation += 1 }
        if key == "stand" { standEscalation += 1 }
    }

    func resetEscalation(_ key: String?) {
        if key == "water" { waterEscalation = 0 }
        if key == "stand" { standEscalation = 0 }
    }

    // 提醒分发：灵动岛胶囊（默认）/ 弹窗强提醒 / 普通通知
    // 升级机制：提醒被忽略 → 下次更大且必须手动点掉；再忽略 → 升级为强弹窗
    func showReminder(icon: String, title: String, message: String, snoozeKey: String?, level: Int = 0) {
        NSSound.beep()
        let effLevel = config.escalateReminders ? level : 0
        switch config.reminderStyle {
        case .notch:
            if effLevel >= 2 {
                showStrongAlert(title: title, message: message, snoozeKey: snoozeKey)
            } else {
                island.showReminder(icon: icon, title: title, message: message, level: effLevel,
                                    onAcknowledge: { self.resetEscalation(snoozeKey) },
                                    onIgnored: { self.bumpEscalation(snoozeKey) })
            }
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
        } else if fullscreenNow {
            line3 = L.t("全屏免打扰中 🎬", "Fullscreen — auto quiet 🎬")
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

    // MARK: 控制台（右键灵动岛打开）

    func toggleSettings() {
        controlCenter.toggle { [weak self] m in self?.wireControlCenter(m) }
    }

    func wireControlCenter(_ m: ControlCenterModel) {
        m.paused = config.paused
        m.launchAtLogin = SMAppService.mainApp.status == .enabled
        m.islandEnabled = config.islandEnabled
        m.waterMinutes = config.waterReminderMinutes
        m.standMinutes = config.standReminderMinutes
        m.repeatMinutes = config.repeatReminderMinutes
        m.breakMinutes = config.breakResetMinutes
        m.quietPeriods = config.quietPeriods
        m.reminderStyle = config.reminderStyle
        m.escalateReminders = config.escalateReminders
        m.breakPraiseEnabled = config.breakPraiseEnabled
        m.fullscreenPause = config.fullscreenPause
        m.weeklyReportEnabled = config.weeklyReportEnabled
        m.islandWidth = config.islandWidth
        m.expandedHeight = config.expandedHeight
        m.pillPadding = config.pillPadding
        m.waterTitle = config.waterTitle
        m.waterMessage = config.waterMessage
        m.standTitle = config.standTitle
        m.standMessage = config.standMessage
        m.onChanged = { self.applySettings(m) }
        m.onStylePreview = { self.previewReminderStyle() }
        m.onPreview = { kind in self.previewReminder(kind) }
        m.onRefreshStats = { self.fillStats(m) }
        m.onOpenDataFolder = { NSWorkspace.shared.open(self.baseDir) }
        m.onExportData = { self.exportData() }
        m.onQuit = { self.quitApp() }
    }

    // 控制台任何字段变化都落到这里
    func applySettings(_ m: ControlCenterModel) {
        config.paused = m.paused
        config.islandEnabled = m.islandEnabled
        config.waterReminderMinutes = m.waterMinutes
        config.standReminderMinutes = m.standMinutes
        config.repeatReminderMinutes = m.repeatMinutes
        config.breakResetMinutes = m.breakMinutes
        config.quietPeriods = m.quietPeriods
        config.reminderStyle = m.reminderStyle
        config.escalateReminders = m.escalateReminders
        config.breakPraiseEnabled = m.breakPraiseEnabled
        config.fullscreenPause = m.fullscreenPause
        config.weeklyReportEnabled = m.weeklyReportEnabled
        config.islandWidth = m.islandWidth
        config.expandedHeight = m.expandedHeight
        config.pillPadding = m.pillPadding
        config.waterTitle = m.waterTitle
        config.waterMessage = m.waterMessage
        config.standTitle = m.standTitle
        config.standMessage = m.standMessage
        saveConfig()

        island.applyAppearance(width: CGFloat(m.islandWidth), expandedHeight: CGFloat(m.expandedHeight), earPadding: CGFloat(m.pillPadding))
        island.start(enabled: config.islandEnabled)
        applyLaunchAtLogin(m.launchAtLogin)
        updateIsland(Date())
    }

    // 把最新统计填进控制台的统计页
    func fillStats(_ m: ControlCenterModel) {
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
        m.bars = bars
        m.weekTotal = weekTotal
        m.todayStats = today()
        m.currentContinuous = sessionStart.map { now.timeIntervalSince($0) } ?? 0
    }

    // 提醒文案：用户自定义优先（支持 {分钟} 占位符），否则默认文案 + 随机小贴士
    func reminderCopy(kind: String, mins: Int, tip: String) -> (title: String, message: String) {
        let defTitle = kind == "water"
            ? L.t("喝口水吧 💧", "Drink some water 💧")
            : L.t("该起来活动了 🧍", "Time to stand up 🧍")
        let customTitle = kind == "water" ? config.waterTitle : config.standTitle
        let customMsg = kind == "water" ? config.waterMessage : config.standMessage
        let title = customTitle.isEmpty ? defTitle : customTitle
        let message: String
        if customMsg.isEmpty {
            message = L.t("已连续使用 \(mins) 分钟。\(tip)", "\(mins) minutes straight. \(tip)")
        } else {
            message = customMsg
                .replacingOccurrences(of: "{分钟}", with: "\(mins)")
                .replacingOccurrences(of: "{minutes}", with: "\(mins)")
        }
        return (title, message)
    }

    // 控制台「效果预览」：真实弹一次对应效果
    func previewReminder(_ kind: String) {
        let tip = L.isZh ? (waterTipsZh.randomElement() ?? "") : (waterTipsEn.randomElement() ?? "")
        switch kind {
        case "water":
            let c = reminderCopy(kind: "water", mins: 42, tip: tip)
            showReminder(icon: "drop.fill", title: c.title, message: c.message, snoozeKey: nil)
        case "stand":
            let c = reminderCopy(kind: "stand", mins: 63, tip: tip)
            showReminder(icon: "figure.stand", title: c.title, message: c.message, snoozeKey: nil)
        case "escalated":
            // 直接演示升级形态（更大、必须手动关闭），不受升级开关影响
            island.showReminder(icon: "exclamationmark.triangle.fill",
                                title: L.t("升级版提醒长这样", "This is the escalated one"),
                                message: L.t("忽略普通提醒后，下一次会变得更大，而且必须手动点掉。",
                                             "Ignored reminders come back bigger and must be dismissed manually."),
                                level: 1, onAcknowledge: {})
        case "celebration":
            island.showCelebration(title: L.t("休息完成 ✅", "Break complete ✅"),
                                   message: L.t("连续工作 1 小时 5 分后休息了一次，这是今日第 3 次休息。",
                                                "You took a real break after 1h 5m — break #3 today."))
        case "weekly":
            island.showCelebration(title: L.t("上周健康报告 📊", "Weekly report 📊"),
                                   message: L.t("上周共用 38 小时 20 分 · 日均 7 小时 40 分 · 最长连续 2 小时 15 分 · 休息 21 次。比上上周多 8%，注意休息。",
                                                "Last week: 38h 20m total · 7h 40m/day · longest 2h 15m · 21 breaks. 8% more than the week before — remember to rest."),
                                   duration: 15)
        default: break
        }
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

    // MARK: 每周健康报告（每周一 9 点后第一次轮询弹出）

    func checkWeeklyReport(now: Date) {
        guard config.weeklyReportEnabled else { return }
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now)   // 2 = 周一
        let hour = cal.component(.hour, from: now)
        guard weekday == 2, hour >= 9, sessionStart != nil else { return }
        guard let monday = cal.date(byAdding: .day, value: -(weekday - 2), to: now) else { return }
        let weekKey = dayFmt.string(from: monday)
        guard stats.lastWeeklyReportWeek != weekKey else { return }
        stats.lastWeeklyReportWeek = weekKey
        saveStats()

        let last = weekStats(endingBefore: monday)
        let prev = weekStats(endingBefore: cal.date(byAdding: .day, value: -7, to: monday) ?? monday)
        guard last.total > 0 else { return }   // 上周没数据就不打扰

        let avg = last.days > 0 ? last.total / Double(last.days) : 0
        var msg = L.t("上周共用 \(fmtDuration(last.total)) · 日均 \(fmtDuration(avg)) · 最长连续 \(fmtDuration(last.longest)) · 休息 \(last.breaks) 次。",
                      "Last week: \(fmtDuration(last.total)) total · \(fmtDuration(avg))/day · longest \(fmtDuration(last.longest)) · \(last.breaks) breaks.")
        if prev.total > 0 {
            let diff = Int(((last.total - prev.total) / prev.total) * 100)
            if abs(diff) >= 3 {
                msg += L.t(diff > 0 ? "比上上周多 \(diff)%，注意休息。" : "比上上周少 \(abs(diff))%，保持得不错。",
                           diff > 0 ? " \(diff)% more than the week before — remember to rest." : " \(abs(diff))% less than the week before. Nice.")
            }
        }
        island.showCelebration(title: L.t("上周健康报告 📊", "Weekly report 📊"), message: msg, duration: 15)
    }

    // 汇总某个周一之前 7 天的数据
    func weekStats(endingBefore monday: Date) -> (total: TimeInterval, days: Int, longest: TimeInterval, breaks: Int) {
        let cal = Calendar.current
        var total: TimeInterval = 0, longest: TimeInterval = 0
        var breaks = 0, activeDays = 0
        for i in 1...7 {
            guard let day = cal.date(byAdding: .day, value: -i, to: monday) else { continue }
            if let d = stats.days[dayFmt.string(from: day)], d.totalActiveSeconds > 0 {
                total += d.totalActiveSeconds
                longest = max(longest, d.longestSessionSeconds)
                breaks += d.breaks
                activeDays += 1
            }
        }
        return (total, activeDays, longest, breaks)
    }

    // MARK: 导出数据

    func exportData() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = L.t("久坐提醒数据-\(todayKey()).json", "UsageReminder-data-\(todayKey()).json")
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            try? FileManager.default.copyItem(at: self.statsURL, to: url)
        }
    }

    @objc func openStats() {
        openStatsWindow()
    }

    // 统计已并入控制台：直接打开控制台并切到统计页
    func openStatsWindow() {
        controlCenter.show(actions: { [weak self] m in self?.wireControlCenter(m) }, tab: .stats)
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
