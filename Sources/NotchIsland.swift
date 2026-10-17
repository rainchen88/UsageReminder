import Cocoa
import SwiftUI

// MARK: - 常驻灵动岛（刘海胶囊）
// 与物理刘海融为一体的设计：
//   · 顶边贴屏幕顶，顶部两侧是向外展开的弧形「肩膀」，与刘海肩部曲线一致
//   · 胶囊与刘海同高（不往下凸、不挡界面），内容放在刘海两侧的耳朵上
//   · 纯黑背景，仅底部圆角，带柔和投影
// 三种形态：
//   pill      常驻胶囊：左耳图标 + 右耳分钟数
//   dashboard 左键点击展开：连续时长 / 今日累计 / 下次提醒倒计时，8 秒自动收起
//   reminder  提醒时展开，点 × 或点按确认后收起
// 右键点击：打开设置面板

enum IslandMode {
    case pill, dashboard, reminder
}

class IslandModel: ObservableObject {
    @Published var mode: IslandMode = .pill
    // 胶囊态
    @Published var pillIcon = "cup.and.saucer"
    @Published var pillText = ""
    @Published var pillTint = Color.white
    // 展开态（看板 / 提醒共用）
    @Published var bigIcon = "cup.and.saucer"
    @Published var line1 = ""
    @Published var line2 = ""
    @Published var line3 = ""

    var onAcknowledge: (() -> Void)?
    var onIgnored: (() -> Void)?
    var onTapPill: () -> Void = {}
    var onDismissReminder: () -> Void = {}

    // 提醒级别：0 = 普通；≥1 = 升级（上次被忽略，更大且必须手动关闭）
    var reminderLevel = 0

    // 刘海下沿深度（胶囊高度与刘海齐平，不往下凸）
    var notchDepth: CGFloat = 38

    // 可调外观（设置里拉动条实时预览）
    @Published var pillWidth: CGFloat = 320        // 胶囊宽度
    @Published var expandedHeight: CGFloat = 122   // 展开看板内容高度
    @Published var earPadding: CGFloat = 20        // 耳朵内容离左右边缘距离

    var size: NSSize {
        switch mode {
        case .pill:      return NSSize(width: pillWidth, height: notchDepth)
        case .dashboard: return NSSize(width: pillWidth + 60, height: notchDepth + expandedHeight)
        case .reminder:
            return reminderLevel == 0
                ? NSSize(width: pillWidth + 100, height: notchDepth + 96)
                : NSSize(width: pillWidth + 180, height: notchDepth + 118)
        }
    }
    var bottomRadius: CGFloat { mode == .pill ? 13 : 20 }
}

// 带右键支持的 hosting view
class IslandHostingView: NSHostingView<IslandView> {
    var onRightClick: (() -> Void)?
    override func rightMouseUp(with event: NSEvent) { onRightClick?() }
}

struct IslandView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        // 黑色背景与圆角由窗口图层负责（动画期间也始终铺满、不闪烁）；
        // 这里只放内容，贴底部（刘海下沿以下），随窗口下边缘移动
        ZStack(alignment: .bottom) {
            Group {
                switch model.mode {
                case .pill:      pillContent.transition(.opacity)
                case .dashboard: dashboardContent.transition(.opacity)
                case .reminder:  reminderContent.transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 胶囊：左耳图标 + 右耳分钟数（中间被物理刘海挡住，正好空着）
    var pillContent: some View {
        HStack(spacing: 0) {
            Image(systemName: model.pillIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(model.pillTint)
            Spacer(minLength: 0)
            if !model.pillText.isEmpty {
                Text(model.pillText)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, model.earPadding)
        .frame(maxWidth: .infinity)
        .frame(height: model.notchDepth)
        .contentShape(Rectangle())
        .onTapGesture { model.onTapPill() }
    }

    // 看板：连续时长 / 今日累计 / 下次提醒
    var dashboardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: model.bigIcon)
                    .font(.title3)
                    .foregroundStyle(.white)
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
        .frame(height: model.expandedHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.onTapPill() }   // 再点一下收起
    }

    // 提醒：图标 + 标题 + 文案 + 关闭按钮
    var reminderContent: some View {
        HStack(spacing: 12) {
            Image(systemName: model.bigIcon)
                .font(.title3)
                .foregroundStyle(.white)
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
                    .foregroundStyle(.white.opacity(0.5))
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
    var onRightClick: (() -> Void)?
    private var panel: NSPanel?
    private var hosting: IslandHostingView?
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
        // 关键：hosting 钉在容器【顶部】（minYMargin 弹性底边）。
        // 黑色背景 + 底部圆角直接画在容器 CALayer 上——图层随窗口动画同步拉伸，
        // 不走 SwiftUI 渲染管线，展开/收起期间顶部始终实心黑色，不闪不露底
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.layer?.cornerRadius = model.bottomRadius
        container.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]  // 仅底部两角
        container.layer?.masksToBounds = true
        let hosting = IslandHostingView(rootView: IslandView(model: model))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .minYMargin]   // 宽度跟随，顶部钉住
        hosting.onRightClick = { [weak self] in self?.onRightClick?() }
        container.addSubview(hosting)
        panel.contentView = container
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        self.panel = panel
        self.hosting = hosting
        reposition(animated: false)
    }

    // MARK: 位置与尺寸（顶边永远贴屏幕顶部）

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func frameFor(size: NSSize) -> NSRect {
        guard let screen = targetScreen() else { return NSRect(origin: .zero, size: size) }
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height   // 顶边贴死屏幕顶，与刘海融为一体
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    // 弹簧曲线伸缩：只由窗口动画驱动，内容钉在顶部、背景铺满，三态连贯
    private func reposition(animated: Bool) {
        guard let panel = panel, let hosting = hosting else { return }
        let newSize = model.size
        // hosting 高度立即就位、顶边对齐容器顶边；窗口动画期间保持钉顶
        hosting.setFrameSize(NSSize(width: panel.contentView?.bounds.width ?? newSize.width,
                                    height: newSize.height))
        hosting.setFrameOrigin(NSPoint(x: 0,
                                       y: (panel.contentView?.bounds.height ?? newSize.height) - newSize.height))
        let frame = frameFor(size: newSize)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.5
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.25, 0.64, 1)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    // 形态切换：内容立即就位（淡入淡出短过渡），窗口弹簧伸缩做主体动画
    private func setMode(_ mode: IslandMode, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.15)) { model.mode = mode }
        } else {
            model.mode = mode
        }
        // 底部圆角跟随形态（窗口图层，平滑过渡）
        if let layer = panel?.contentView?.layer {
            CATransaction.begin()
            CATransaction.setAnimationDuration(animated ? 0.5 : 0)
            layer.cornerRadius = model.bottomRadius
            CATransaction.commit()
        }
        reposition(animated: animated)
    }

    // MARK: 每 5 秒喂一次状态

    // 外观实时预览：滑条拖动时立即改变尺寸（弹簧动画过渡）
    func applyAppearance(width: CGFloat, expandedHeight: CGFloat, earPadding: CGFloat) {
        let sizeChanged = width != model.pillWidth || expandedHeight != model.expandedHeight
        model.pillWidth = width
        model.expandedHeight = expandedHeight
        model.earPadding = earPadding
        if sizeChanged, panel != nil { reposition(animated: true) }
    }

    func update(icon: String, text: String, tint: Color,
                line1: String, line2: String, line3: String) {
        model.pillIcon = icon
        model.pillText = text
        model.pillTint = tint
        // 提醒展开期间不覆盖内容，否则提醒文案会被看板数据冲掉
        guard model.mode != .reminder else { return }
        model.bigIcon = icon
        model.line1 = line1
        model.line2 = line2
        model.line3 = line3
    }

    // MARK: 看板展开 / 收起

    func toggleDashboard() {
        switch model.mode {
        case .pill:
            setMode(.dashboard)
            scheduleCollapse()
        case .dashboard:
            setMode(.pill)
            collapseWork?.cancel()
        case .reminder:
            break
        }
    }

    private func scheduleCollapse() {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.model.mode == .dashboard else { return }
            self.setMode(.pill)
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    // MARK: 提醒

    // level 0 = 普通提醒（25 秒自动收起）；level ≥1 = 升级提醒（更大、必须手动点掉）
    func showReminder(icon: String, title: String, message: String, level: Int = 0,
                      onAcknowledge: @escaping () -> Void, onIgnored: (() -> Void)? = nil) {
        ensurePanel()
        collapseWork?.cancel()
        reminderWork?.cancel()
        model.bigIcon = icon
        model.line1 = title
        model.line2 = message
        model.reminderLevel = level
        model.onAcknowledge = onAcknowledge
        model.onIgnored = onIgnored
        panel?.orderFrontRegardless()
        setMode(.reminder)

        if level == 0 {
            // 25 秒未确认自动收起（不算确认，触发升级逻辑）
            let work = DispatchWorkItem { [weak self] in self?.collapseFromReminder(ack: false) }
            reminderWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: work)
        }
    }

    // 休息打卡 / 周报：短暂展开的卡片，默认 4 秒自动收起
    func showCelebration(title: String, message: String, duration: TimeInterval = 4) {
        ensurePanel()
        collapseWork?.cancel()
        reminderWork?.cancel()
        model.bigIcon = "checkmark.circle.fill"
        model.line1 = title
        model.line2 = message
        model.reminderLevel = 0
        model.onAcknowledge = nil
        model.onIgnored = nil
        panel?.orderFrontRegardless()
        setMode(.reminder)

        let work = DispatchWorkItem { [weak self] in self?.collapseFromReminder(ack: false) }
        reminderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func dismissReminder() { collapseFromReminder(ack: true) }

    private func collapseFromReminder(ack: Bool) {
        guard model.mode == .reminder else { return }
        reminderWork?.cancel()
        if ack { model.onAcknowledge?() } else { model.onIgnored?() }
        model.onAcknowledge = nil
        model.onIgnored = nil
        model.reminderLevel = 0
        setMode(.pill)
        if !islandEnabled { panel?.close() }
    }
}
