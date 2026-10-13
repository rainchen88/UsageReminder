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

// 刘海轮廓：顶边比身体宽，两侧肩膀是平滑的四分之一圆弧
// （弧线与顶边水平相切、与侧壁垂直相切——与 MacBook 刘海肩部一致）；底部圆角
struct NotchCapsuleShape: Shape {
    var topFillet: CGFloat      // 肩部外扩宽度/深度
    var bottomRadius: CGFloat   // 底部圆角

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topFillet, bottomRadius) }
        set { topFillet = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let f = topFillet, b = bottomRadius
        let w = rect.width, h = rect.height
        let k: CGFloat = 0.5523   // 四分之一圆的贝塞尔近似系数
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        // 右肩：顶边(宽) → 侧壁(窄)，水平进、垂直出的外扩弧线
        p.addCurve(to: CGPoint(x: w - f, y: f),
                   control1: CGPoint(x: w - k * f, y: 0),
                   control2: CGPoint(x: w - f, y: f - k * f))
        p.addLine(to: CGPoint(x: w - f, y: h - b))
        p.addQuadCurve(to: CGPoint(x: w - f - b, y: h), control: CGPoint(x: w - f, y: h))   // 右下圆角
        p.addLine(to: CGPoint(x: f + b, y: h))
        p.addQuadCurve(to: CGPoint(x: f, y: h - b), control: CGPoint(x: f, y: h))           // 左下圆角
        p.addLine(to: CGPoint(x: f, y: f))
        // 左肩（镜像）
        p.addCurve(to: CGPoint(x: 0, y: 0),
                   control1: CGPoint(x: f, y: f - k * f),
                   control2: CGPoint(x: k * f, y: 0))
        p.closeSubpath()
        return p
    }
}

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
    var onTapPill: () -> Void = {}
    var onDismissReminder: () -> Void = {}

    // 刘海下沿深度（胶囊高度与刘海齐平，不往下凸）
    var notchDepth: CGFloat = 38

    var size: NSSize {
        switch mode {
        case .pill:      return NSSize(width: 320, height: notchDepth)
        case .dashboard: return NSSize(width: 380, height: notchDepth + 122)
        case .reminder:  return NSSize(width: 420, height: notchDepth + 96)
        }
    }
    var topFillet: CGFloat { mode == .pill ? 10 : 14 }
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
        // 背景形状铺满整个窗口（动画时窗口拉伸，形状随之铺满，不会出现空洞）；
        // 内容贴底部（刘海下沿以下），窗口生长时内容随下边缘移动
        ZStack(alignment: .bottom) {
            NotchCapsuleShape(topFillet: model.topFillet, bottomRadius: model.bottomRadius)
                .fill(Color.black)
            Group {
                switch model.mode {
                case .pill:      pillContent.transition(.opacity)
                case .dashboard: dashboardContent.transition(.opacity)
                case .reminder:  reminderContent.transition(.opacity)
                }
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 3)
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
        .padding(.horizontal, 20)
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
        .frame(height: 122)
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
        // NSHostingView + 显式 frame：NSHostingController 会按内容理想尺寸重设窗口，导致塌缩
        // 关键：hosting 钉在容器【顶部】（minYMargin 弹性底边）。
        // 展开时窗口向下生长，顶部逐渐被揭示，绝不留透明空洞
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let hosting = IslandHostingView(rootView: IslandView(model: model))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .minYMargin]   // 宽度跟随，顶部钉住
        hosting.onRightClick = { [weak self] in self?.onRightClick?() }
        container.addSubview(hosting)
        panel.contentView = container
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

    // 形态切换：内容立即就位（形状圆角与淡入淡出短过渡），窗口弹簧伸缩做主体动画
    private func setMode(_ mode: IslandMode, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.15)) { model.mode = mode }
        } else {
            model.mode = mode
        }
        reposition(animated: animated)
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

    func showReminder(icon: String, title: String, message: String,
                      onAcknowledge: @escaping () -> Void) {
        ensurePanel()
        collapseWork?.cancel()
        reminderWork?.cancel()
        model.bigIcon = icon
        model.line1 = title
        model.line2 = message
        model.onAcknowledge = onAcknowledge
        panel?.orderFrontRegardless()
        setMode(.reminder)

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
        setMode(.pill)
        if !islandEnabled { panel?.close() }
    }
}
