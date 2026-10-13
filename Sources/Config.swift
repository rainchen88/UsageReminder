import Foundation

// MARK: - 本地化（跟随系统语言）

enum L {
    static let isZh = Locale.current.language.languageCode?.identifier == "zh"
    static func t(_ zh: String, _ en: String) -> String { isZh ? zh : en }
}

// MARK: - 配置

struct Config: Codable {
    var waterReminderMinutes: Int = 45   // 喝水提醒阈值（0 = 关闭）
    var standReminderMinutes: Int = 60   // 站立提醒阈值（0 = 关闭）
    var breakResetMinutes: Int = 5       // 无操作多久算「已休息」
    var repeatReminderMinutes: Int = 15  // 未休息时每隔多久重复提醒
    var quietHoursStart: Int = -1        // 免打扰开始小时（-1 = 关闭）
    var quietHoursEnd: Int = -1          // 免打扰结束小时
    var gentleMode: Bool = false         // 温和提醒（普通通知，自动消失）
    var paused: Bool = false

    init() {}

    // 旧版本配置缺少新增字段时用默认值补齐，避免升级后配置被重置
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        waterReminderMinutes = try c.decodeIfPresent(Int.self, forKey: .waterReminderMinutes) ?? 45
        standReminderMinutes = try c.decodeIfPresent(Int.self, forKey: .standReminderMinutes) ?? 60
        breakResetMinutes = try c.decodeIfPresent(Int.self, forKey: .breakResetMinutes) ?? 5
        repeatReminderMinutes = try c.decodeIfPresent(Int.self, forKey: .repeatReminderMinutes) ?? 15
        quietHoursStart = try c.decodeIfPresent(Int.self, forKey: .quietHoursStart) ?? -1
        quietHoursEnd = try c.decodeIfPresent(Int.self, forKey: .quietHoursEnd) ?? -1
        gentleMode = try c.decodeIfPresent(Bool.self, forKey: .gentleMode) ?? false
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
    }
}

// MARK: - 统计数据

struct Session: Codable {
    var start: TimeInterval
    var end: TimeInterval
    var seconds: TimeInterval
}

struct DayStats: Codable {
    var totalActiveSeconds: TimeInterval = 0
    var sessions: [Session] = []
    var waterReminders: Int = 0
    var standReminders: Int = 0
    var breaks: Int = 0
    var longestSessionSeconds: TimeInterval = 0
}

struct StatsStore: Codable {
    var days: [String: DayStats] = [:]
}

// MARK: - 工具

func fmtDuration(_ seconds: TimeInterval) -> String {
    let s = Int(seconds)
    let h = s / 3600, m = (s % 3600) / 60
    if L.isZh {
        return h > 0 ? "\(h) 小时 \(m) 分" : "\(m) 分钟"
    }
    return h > 0 ? "\(h)h \(m)m" : "\(m)m"
}

func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}
