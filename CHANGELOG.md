# Changelog

## v0.6.3 · 2026-10-17

- 修复：重启 / 更新 App 后「连续使用」计时清零。进行中的会话起点现在持久化到本地，重启后无缝续算；若重启时正在休息，则按最后活跃时间正常收尾并计一次休息 / Fix: the continuous-use timer reset to zero after app restart/update. The ongoing session start is now persisted and resumed seamlessly; if you're idle at relaunch, the previous session is closed out properly and counts as a break
- 退出/被终止（SIGTERM）时立即落盘统计数据，覆盖安装更新不再丢失最后一段时长 / Stats are flushed to disk on quit/SIGTERM — updating no longer loses the last minutes

## v0.6.2 · 2026-10-17

- 全英文界面：界面语言跟随系统（英文系统下控制台 / 灵动岛 / 提醒 / 统计全部英文），并修复 `-AppleLanguages` 强制语言不生效的问题 / Full English UI: every surface follows the system language; fixed `-AppleLanguages` override not taking effect
- 应用名多语言：英文系统下访达与程序坞显示「UsageReminder」/ Localized app name — shows as "UsageReminder" on English systems
- 分发格式改为 DMG 拖动安装盘（含 Applications 快捷方式），不再使用 zip；build.sh 一键产出 `久坐提醒-版本号.dmg` / Distribution switched from zip to a drag-install DMG (with Applications shortcut); build.sh now produces `久坐提醒-<version>.dmg`
- 导出数据文件名跟随语言 / Exported data file name follows the UI language

## v0.6.1 · 2026-10-17

- 控制台左侧导航整行可点击（不再只有点中文字/图标才生效）/ Sidebar rows are now fully clickable, not just the label
- 新增「文字离左右边缘距离」滑条（8–100pt）：胶囊耳朵上的图标和分钟数离屏幕边缘多远可调，实时预览 / New "edge padding" slider (8–100pt): how far the ear icon/minutes sit from the screen edges, with live preview

## v0.6 · 2026-10-17

- 全新「控制台」：设置 + 外观 + 提醒 + 统计合并为一个黑色独立窗口（左侧导航四页），窗口位置自动记忆 / New Control Center: settings, appearance, reminders and stats merged into one black window with sidebar navigation; remembers its position
- 灵动岛尺寸可调：胶囊宽度（240–560pt）与展开看板高度（90–200pt）拉动条，拖动实时预览，一键恢复默认 / Adjustable island size: capsule width & expanded height sliders with live preview and one-click reset
- 提醒文案自定义：喝水 / 站立的标题与正文均可修改，正文支持 {分钟} 占位符，留空回退默认 / Custom reminder text for water & stand (title + body), {分钟} placeholder supported, blank falls back to default
- 效果预览：控制台里一键真实演示喝水 / 站立 / 升级版提醒 / 休息打卡 / 周报五种效果 / Preview buttons fire a real demo of each of the five reminder effects
- 原右键小设置面板与独立统计窗口退役 / The old right-click mini panel and standalone stats window are retired

## v0.5 · 2026-10-17

- 数据目录统一为 `~/Library/Application Support/UsageReminder/`，更新 App 不再丢失统计与设置；首次启动自动迁移旧数据 / Data unified into `~/Library/Application Support/UsageReminder/` — updating the app no longer resets stats & settings; legacy data auto-migrated on first launch
- 提醒被忽略后逐渐加强：灵动岛提醒 25 秒不点会变大变醒目，再忽略升级为强弹窗；可在设置关闭 / Escalating reminders: ignored island reminders grow more prominent, then escalate to a modal alert; can be disabled
- 休息打卡：真正离开电脑休息达标后，灵动岛弹出鼓励动画 / Break celebration: the island cheers when you actually take a qualifying break
- 全屏自动免打扰：前台 App 全屏（视频会议/观影）时自动暂停提醒，岛上显示「全屏免打扰中 🎬」/ Auto quiet hours while a fullscreen app is frontmost (meetings/movies)
- 每周一健康报告：汇总上周使用时长、最长连续使用、休息次数，并与上上周对比 / Weekly Monday report: last week's totals, longest session, breaks, week-over-week trend
- 设置面板新增「导出数据…」，一键导出统计 JSON / New "Export data…" button in settings
- 修复：看板轮询覆盖提醒文案；展开时顶部偶发闪烁 / Fix: dashboard polling overwrote reminder text; occasional top flicker while expanding

## v0.4 · 2026-10-13

- 灵动岛重设计：与刘海同高（不再凸出遮挡界面），顶部改为与刘海一致的肩部外弧线 / Island redesigned: flush with the notch height (no longer covers app UI), shoulder curves matching the physical notch
- 胶囊收窄，内容分居两侧耳朵：左耳图标、右耳分钟数 / Slimmer capsule; icon on the left ear, minutes on the right ear
- 菜单栏图标移除：所有设置搬进灵动岛右键设置面板（阈值 / 免打扰 / 提醒方式 / 自启动 / 暂停 / 退出）/ Menu-bar icon removed: all settings moved into the island's right-click settings panel
- 展开/收起改为弹簧动画 / Spring animation for expand & collapse
- 图标统一为白色，更贴近刘海质感 / All-white icons matching the notch aesthetic

## v0.3.5 · 2026-10-13

- 灵动岛改为与刘海同高，不再向下凸出遮挡程序界面；内容放在刘海两侧的「耳朵」上：左耳图标、右耳分钟数 / Island is now flush with the notch height and no longer covers app content; icon on the left ear, minutes on the right ear
- 休息状态图标改为低调的白色 / Resting icon now understated white
- 展开动画与圆角更贴合刘海曲线 / Expansion corners and animation tuned to match the notch

## v0.3.4 · 2026-10-13

- 灵动岛与物理刘海融为一体：顶边贴死屏幕顶、纯黑、仅底部圆角、带柔和投影，内容显示在刘海下沿的可见区域 / Island now merges with the physical notch: flush top, pure black, bottom-only rounded corners, soft shadow; content sits below the notch edge
- 修复胶囊被物理刘海遮挡看不见的问题 / Fix capsule being hidden behind the physical notch

## v0.3.3 · 2026-10-13

- 灵动岛常驻：刘海下方胶囊实时显示连续使用时长，久坐升温变色（青→橙→红）/ Always-on Dynamic Island capsule under the notch showing live session minutes, heating up teal → orange → red
- 点击胶囊展开小看板：当前时长、今日累计、下次提醒倒计时，8 秒自动收起 / Tap the capsule to expand a mini dashboard (session, today, next reminder countdown), auto-collapses
- 提醒从灵动岛展开并新增关闭按钮；25 秒未确认自动收起 / Reminders expand from the island with a close button; auto-dismiss after 25s
- 胶囊背景改为实色，任意壁纸/窗口下文字都清晰 / Solid capsule background for readability over any content
- 新增「灵动岛常驻显示」开关 / New "always-on island" toggle in the menu
- 修复胶囊窗口塌缩为 0×0 的问题（改用 NSHostingView + 显式 frame）/ Fix capsule collapsing to 0×0 (NSHostingView with explicit frame)

## v0.3.2 · 2026-10-13

- 灵动岛胶囊提醒（默认）：贴着刘海/屏幕顶部滑出的黑色胶囊，一键关闭，不打断输入 / Dynamic-Island-style notch capsule reminder (default): a black capsule sliding down under the notch, one-click dismiss, no keyboard focus stolen
- 提醒方式三选一：灵动岛胶囊 / 强提醒弹窗 / 温和通知，菜单切换立即预览 / Three reminder styles (notch capsule, strong alert, gentle banner), switchable from the menu with instant preview
- 免打扰升级为多选时段：午休 / 晚间 / 夜间任意组合，支持跨午夜 / Do-not-disturb is now multi-select: lunch, evening and overnight presets in any combination, midnight-crossing supported
- 修复 NSPanel 初始化方式导致的提醒窗口不显示问题 / Fix reminder panel not showing due to NSPanel styleMask initialization
- build.sh 集成 ad-hoc 签名与纯净打包，产出可直接分享的 zip / build.sh now signs (ad-hoc) and packages a share-ready zip

## v0.3.1 · 2026-10-13

- 新增免打扰时段（午休 / 夜间预设，支持跨午夜）/ Quiet hours presets (lunch break, overnight)
- 久坐后成功休息会收到鼓励通知 / Praise notification after taking a real break
- 统计窗口新增近 7 天总计与日均 / Weekly total & daily average in stats window
- 修复旧版本配置升级时被重置的问题 / Fix config reset on upgrade (backward-compatible decoding)
- 代码拆分为多文件结构 / Codebase split into multiple source files

## v0.3 · 2026-10-13

- 中英双语界面，自动跟随系统语言 / Bilingual UI (中文 & English, follows system language)
- 新增温和提醒模式：普通通知自动消失，不打断工作 / Gentle mode with auto-dismissing banners
- 修复统计窗口在多显示器环境下尺寸塌缩的问题 / Fix stats window collapsing to 1pt on multi-display setups
- README 双语化，新增截图与徽章 / Bilingual README with screenshots and badges

## v0.2 · 2026-10-13

- 统计详情窗口（近 7 天柱状图 + 今日明细）
- 菜单栏看板：倒计时、近 7 天概览
- 开机自动启动开关
- 健康小贴士
- 应用图标、通用二进制（arm64 + x86_64）

## v0.1 · 2026-10-13

- 首个版本：连续使用监控、喝水/站立强提醒、休息自动判定、今日统计
