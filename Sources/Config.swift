import Foundation

// MARK: - 本地化（跟随系统语言）

enum L {
    static let isZh = Locale.current.language.languageCode?.identifier == "zh"
    static func t(_ zh: String, _ en: String) -> String { isZh ? zh : en }
}

// MARK: - 配置

// 提醒方式：notch（灵动岛胶囊）/ strong（弹窗强提醒）/ gentle（普通通知）
enum ReminderStyle: String, Codable {
    case notch, strong, gentle
}

struct Config: Codable {
    var waterReminderMinutes: Int = 45   // 喝水提醒阈值（0 = 关闭）
    var standReminderMinutes: Int = 60   // 站立提醒阈值（0 = 关闭）
    var breakResetMinutes: Int = 5       // 无操作多久算「已休息」
    var repeatReminderMinutes: Int = 15  // 未休息时每隔多久重复提醒
    var quietPeriods: [[Int]] = []       // 免打扰时段列表，如 [[12,14],[22,8]]，支持多选
    var reminderStyle: ReminderStyle = .notch
    var paused: Bool = false

    init() {}

    // 向后兼容：旧字段 gentleMode / quietHoursStart/End 自动迁移，缺失字段用默认值
    enum CodingKeys: String, CodingKey {
        case waterReminderMinutes, standReminderMinutes, breakResetMinutes
        case repeatReminderMinutes, quietPeriods, reminderStyle, paused
        case gentleMode, quietHoursStart, quietHoursEnd   // 仅用于读取旧配置
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        waterReminderMinutes = try c.decodeIfPresent(Int.self, forKey: .waterReminderMinutes) ?? 45
        standReminderMinutes = try c.decodeIfPresent(Int.self, forKey: .standReminderMinutes) ?? 60
        breakResetMinutes = try c.decodeIfPresent(Int.self, forKey: .breakResetMinutes) ?? 5
        repeatReminderMinutes = try c.decodeIfPresent(Int.self, forKey: .repeatReminderMinutes) ?? 15
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false

        if let style = try c.decodeIfPresent(ReminderStyle.self, forKey: .reminderStyle) {
            reminderStyle = style
        } else if try c.decodeIfPresent(Bool.self, forKey: .gentleMode) ?? false {
            reminderStyle = .gentle   // 旧版温和模式迁移
        }

        if let periods = try c.decodeIfPresent([[Int]].self, forKey: .quietPeriods) {
            quietPeriods = periods
        } else if let s = try c.decodeIfPresent(Int.self, forKey: .quietHoursStart),
                  let e = try c.decodeIfPresent(Int.self, forKey: .quietHoursEnd),
                  s >= 0, e >= 0 {
            quietPeriods = [[s, e]]   // 旧版单区间迁移
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(waterReminderMinutes, forKey: .waterReminderMinutes)
        try c.encode(standReminderMinutes, forKey: .standReminderMinutes)
        try c.encode(breakResetMinutes, forKey: .breakResetMinutes)
        try c.encode(repeatReminderMinutes, forKey: .repeatReminderMinutes)
        try c.encode(quietPeriods, forKey: .quietPeriods)
        try c.encode(reminderStyle, forKey: .reminderStyle)
        try c.encode(paused, forKey: .paused)
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
