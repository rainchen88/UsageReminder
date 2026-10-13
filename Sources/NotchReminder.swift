import Cocoa
import SwiftUI

// MARK: - 灵动岛式提醒（刘海胶囊）

struct NotchReminderView: View {
    let icon: String
    let title: String
    let message: String
    let onTap: () -> Void

    @State private var show = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout).bold()
                    .foregroundStyle(.white)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 420, height: 96)   // 固定尺寸，与面板一致
        .background(.black.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .scaleEffect(x: 1, y: show ? 1 : 0.05, anchor: .top)
        .opacity(show ? 1 : 0)
        .onAppear {
            // 延迟一帧再触发动画，避免窗口尚未上屏时动画被吞掉导致内容停在透明态
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { show = true }
            }
        }
        .onTapGesture { onTap() }
        .contentShape(Rectangle())
    }
}

class NotchReminderController {
    private var panel: NSPanel?
    private var autoDismiss: DispatchWorkItem?

    func show(icon: String, title: String, message: String, onAcknowledge: @escaping () -> Void) {
        dismiss(animated: false)

        let view = NotchReminderView(icon: icon, title: title, message: message) { [weak self] in
            onAcknowledge()
            self?.dismiss(animated: true)
        }

        let size = NSSize(width: 420, height: 96)
        // 用指定初始化器创建无边框面板（事后改 styleMask 对 NSPanel 不生效）
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.contentViewController = NSHostingController(rootView: view)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        // 优先放在有刘海的屏幕上，与刘海底部对齐；没有刘海就贴顶部中央
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
        if let screen = screen {
            let x = screen.frame.midX - size.width / 2
            let notchDepth = screen.safeAreaInsets.top   // 刘海深度（无刘海为 0）
            let y = screen.frame.maxY - notchDepth - size.height + 6
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        self.panel = panel
        FileHandle.standardOutput.write("[notch] shown frame=\(panel.frame) visible=\(panel.isVisible) screen=\(screen?.frame ?? .zero) notchDepth=\(screen?.safeAreaInsets.top ?? -1)\n".data(using: .utf8)!)

        // 12 秒未点则自动消失（不算已确认）
        let work = DispatchWorkItem { [weak self] in self?.dismiss(animated: true) }
        autoDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
    }

    func dismiss(animated: Bool) {
        autoDismiss?.cancel()
        autoDismiss = nil
        guard let panel = panel else { return }
        self.panel = nil
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.close()
            })
        } else {
            panel.close()
        }
    }
}
