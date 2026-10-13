import Cocoa

// ============================================================
// 久坐提醒 UsageReminder
// 监控连续电脑使用时长，提醒喝水/站立，统计每日使用情况
// 中英双语界面（跟随系统语言），支持强提醒/温和提醒/免打扰
// ============================================================

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // 纯菜单栏应用，不出现在 Dock
let delegate = AppDelegate()
app.delegate = delegate
app.run()
