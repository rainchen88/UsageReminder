# Changelog

## v3.2 · 2026-10-13

- 灵动岛胶囊提醒（默认）：贴着刘海/屏幕顶部滑出的黑色胶囊，一键关闭，不打断输入 / Dynamic-Island-style notch capsule reminder (default): a black capsule sliding down under the notch, one-click dismiss, no keyboard focus stolen
- 提醒方式三选一：灵动岛胶囊 / 强提醒弹窗 / 温和通知，菜单切换立即预览 / Three reminder styles (notch capsule, strong alert, gentle banner), switchable from the menu with instant preview
- 免打扰升级为多选时段：午休 / 晚间 / 夜间任意组合，支持跨午夜 / Do-not-disturb is now multi-select: lunch, evening and overnight presets in any combination, midnight-crossing supported
- 修复 NSPanel 初始化方式导致的提醒窗口不显示问题 / Fix reminder panel not showing due to NSPanel styleMask initialization
- build.sh 集成 ad-hoc 签名与纯净打包，产出可直接分享的 zip / build.sh now signs (ad-hoc) and packages a share-ready zip

## v3.1 · 2026-10-13

- 新增免打扰时段（午休 / 夜间预设，支持跨午夜）/ Quiet hours presets (lunch break, overnight)
- 久坐后成功休息会收到鼓励通知 / Praise notification after taking a real break
- 统计窗口新增近 7 天总计与日均 / Weekly total & daily average in stats window
- 修复旧版本配置升级时被重置的问题 / Fix config reset on upgrade (backward-compatible decoding)
- 代码拆分为多文件结构 / Codebase split into multiple source files

## v3.0 · 2026-10-13

- 中英双语界面，自动跟随系统语言 / Bilingual UI (中文 & English, follows system language)
- 新增温和提醒模式：普通通知自动消失，不打断工作 / Gentle mode with auto-dismissing banners
- 修复统计窗口在多显示器环境下尺寸塌缩的问题 / Fix stats window collapsing to 1pt on multi-display setups
- README 双语化，新增截图与徽章 / Bilingual README with screenshots and badges

## v2.0 · 2026-10-13

- 统计详情窗口（近 7 天柱状图 + 今日明细）
- 菜单栏看板：倒计时、近 7 天概览
- 开机自动启动开关
- 健康小贴士
- 应用图标、通用二进制（arm64 + x86_64）

## v1.0 · 2026-10-13

- 首个版本：连续使用监控、喝水/站立强提醒、休息自动判定、今日统计
