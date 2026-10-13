import Cocoa
import SwiftUI

// MARK: - 常驻灵动岛（刘海胶囊）
// 设计要点（与物理刘海融为一体）：
//   · 顶边贴屏幕顶、比刘海更宽更高，超出刘海的部分自然「露出来」
//   · 纯黑背景（与刘海硬件同色），只有底部两个圆角，顶部直角
//   · 内容放在刘海下沿以下的可见区域（safeAreaInsets.top ≈ 38pt）
// 三种形态：
//   pill      胶囊常驻：图标 + 连续使用分钟数，颜色随久坐时长升温（青→橙→红）
//   dashboard 点击胶囊展开：连续时长 / 今日累计 / 下次提醒倒计时，8 秒自动收起
//   reminder  提醒时展开为大胶囊，点 × 或点按确认后收起

enum IslandMode {
    case pill, dashboard, reminder
}

class IslandModel: ObservableObject {
    @Published var mode: IslandMode = .pill
    // 胶囊态
    @Published var pillIcon = "cup.and.saucer"
    @Published var pillText = ""
    @Published var pillTint = Color.teal
    // 展开态（看板 / 提醒共用）
    @Published var bigIcon = "cup.and.saucer"
    @Published var line1 = ""
    @Published var line2 = ""
    @Published var line3 = ""

    var onAcknowledge: (() -> Void)?
    var onTapPill: () -> Void = {}
    var onDismissReminder: () -> Void = {}

    // 刘海下沿深度（胶囊高度与刘海齐平，不往下凸）
    var notchDepth: CGFloat = 38

    var size: NSSize {
        switch mode {
        case .pill:      return NSSize(width: 340, height: notchDepth)          // 与刘海同高，内容在两侧耳朵
        case .dashboard: return NSSize(width: 400, height: notchDepth + 122)
        case .reminder:  return NSSize(width: 440, height: notchDepth + 96)
        }
    }
    var bottomRadius: CGFloat { mode == .pill ? 10 : 20 }
}

struct IslandView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)   // 上半部分藏在物理刘海后面
            // 可见内容区（刘海下沿以下）
            Group {
                switch model.mode {
                case .pill:      pillContent
                case .dashboard: dashboardContent
                case .reminder:  reminderContent
                }
            }
        }
        .frame(width: model.size.width, height: model.size.height)
        .background(Color.black)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: model.bottomRadius,
                                          bottomTrailingRadius: model.bottomRadius,
                                          style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)
    }

    // 胶囊：左耳朵图标 + 右耳朵分钟数（中间被物理刘海挡住，正好空着）
    var pillContent: some View {
        HStack(spacing: 0) {
            Image(systemName: model.pillIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.pillTint)
            Spacer(minLength: 0)
            if !model.pillText.isEmpty {
                Text(model.pillText)
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.onTapPill() }
    }

    // 看板：连续时长 / 今日累计 / 下次提醒
    var dashboardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: model.bigIcon)
                    .font(.title2)
                    .foregroundStyle(model.pillTint)
                Text(model.line1)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
            }
            Text(model.line2)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
            Text(model.line3)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .frame(height: 122)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.onTapPill() }   // 再点一下收起
    }

    // 提醒：图标 + 标题 + 文案 + 关闭按钮
    var reminderContent: some View {
        HStack(spacing: 12) {
            Image(systemName: model.bigIcon)
                .font(.title2)
                .foregroundStyle(model.pillTint)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.line1)
                    .font(.callout).bold()
                    .foregroundStyle(.white)
                Text(model.line2)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: { model.onDismissReminder() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .frame(height: 96)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.onDismissReminder() }   // 点按也算确认
    }
}

class NotchIslandController {
    let model = IslandModel()
    private var panel: NSPanel?
    private var hosting: NSHostingView<IslandView>?
    private var collapseWork: DispatchWorkItem?    // 看板自动收起
    private var reminderWork: DispatchWorkItem?    // 提醒自动消失
    private(set) var islandEnabled = true          // 胶囊是否常驻（提醒不受此开关影响）

    init() {
        model.onTapPill = { [weak self] in self?.toggleDashboard() }
        model.onDismissReminder = { [weak self] in self?.dismissReminder() }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.reposition(animated: false)
        }
    }

    // MARK: 生命周期

    func start(enabled: Bool) {
        islandEnabled = enabled
        ensurePanel()
        if enabled {
            panel?.orderFrontRegardless()
        } else if model.mode == .pill {
            panel?.close()
        }
    }

    private func ensurePanel() {
        if panel != nil { return }
        // 用目标屏幕的真实刘海深度
        if let screen = targetScreen(), screen.safeAreaInsets.top > 0 {
            model.notchDepth = screen.safeAreaInsets.top
        }
        let size = model.size
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        // NSHostingView + 显式 frame：NSHostingController 会按内容理想尺寸重设窗口，导致塌缩
        let hosting = NSHostingView(rootView: IslandView(model: model))
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false   // 阴影由 SwiftUI 侧绘制，避免方角阴影穿帮
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        self.panel = panel
        self.hosting = hosting
        reposition(animated: false)
    }

    // MARK: 位置与尺寸（顶边永远贴屏幕顶部，动画只变高度/宽度）

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func frameFor(size: NSSize) -> NSRect {
        guard let screen = targetScreen() else { return NSRect(origin: .zero, size: size) }
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height   // 顶边贴死屏幕顶，与刘海融为一体
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func reposition(animated: Bool) {
        guard let panel = panel else { return }
        let frame = frameFor(size: model.size)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        hosting?.frame = NSRect(origin: .zero, size: model.size)
    }

    // MARK: 每 5 秒喂一次状态

    func update(icon: String, text: String, tint: Color,
                line1: String, line2: String, line3: String) {
        model.pillIcon = icon
        model.pillText = text
        model.pillTint = tint
        model.bigIcon = icon
        model.line1 = line1
        model.line2 = line2
        model.line3 = line3
    }

    // MARK: 看板展开 / 收起

    func toggleDashboard() {
        switch model.mode {
        case .pill:
            model.mode = .dashboard
            reposition(animated: true)
            scheduleCollapse()
        case .dashboard:
            model.mode = .pill
            reposition(animated: true)
            collapseWork?.cancel()
        case .reminder:
            break
        }
    }

    private func scheduleCollapse() {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.model.mode == .dashboard else { return }
            self.model.mode = .pill
            self.reposition(animated: true)
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    // MARK: 提醒

    func showReminder(icon: String, title: String, message: String, tint: Color = .teal,
                      onAcknowledge: @escaping () -> Void) {
        ensurePanel()
        collapseWork?.cancel()
        reminderWork?.cancel()
        model.bigIcon = icon
        model.line1 = title
        model.line2 = message
        model.pillTint = tint
        model.onAcknowledge = onAcknowledge
        model.mode = .reminder
        panel?.orderFrontRegardless()
        reposition(animated: true)

        // 25 秒未确认自动收起（不算确认，重复提醒逻辑照常）
        let work = DispatchWorkItem { [weak self] in self?.collapseFromReminder(ack: false) }
        reminderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: work)
    }

    func dismissReminder() { collapseFromReminder(ack: true) }

    private func collapseFromReminder(ack: Bool) {
        guard model.mode == .reminder else { return }
        reminderWork?.cancel()
        if ack { model.onAcknowledge?() }
        model.onAcknowledge = nil
        model.mode = .pill
        reposition(animated: true)
        if !islandEnabled { panel?.close() }
    }
}
