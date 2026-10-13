# Contributing

感谢你对 UsageReminder 感兴趣！/ Thanks for your interest in contributing!

## 开发环境

- macOS 14+，Xcode Command Line Tools（`xcode-select --install`）
- 无需 Xcode 工程、无第三方依赖，纯 Swift + 系统框架

## 构建与调试

```bash
./build.sh          # 构建 久坐提醒.app
# 调试模式（打印状态日志）：
./久坐提醒.app/Contents/MacOS/UsageReminder --debug
# 预览统计窗口：
./久坐提醒.app/Contents/MacOS/UsageReminder --show-stats
# 测试强提醒弹窗：
./久坐提醒.app/Contents/MacOS/UsageReminder --test-alert
```

## 代码结构

```
Sources/
├── main.swift        # 入口
├── AppDelegate.swift # 主逻辑：轮询、提醒、菜单、窗口
├── Config.swift      # 配置与数据结构、本地化工具
├── IdleTime.swift    # IOKit 空闲时间读取
├── StatsView.swift   # SwiftUI 统计窗口
└── Tips.swift        # 健康小贴士文案
```

## 提交 PR

1. Fork 并创建分支
2. 保持「无网络、无权限索取、数据本地化」的原则
3. 用户可见文案需要中英双语（`L.t(zh, en)`）
4. 提交前确保 `./build.sh` 通过

## 报告问题

提 Issue 时请附上：macOS 版本、芯片（Apple Silicon / Intel）、复现步骤、`--debug` 模式的日志输出。
