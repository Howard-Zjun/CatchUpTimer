# CatchUpTimer

基于 Swift、Foundation Timer 和 UIKit 生命周期通知的定时器组件。

## 核心特性

- 支持启动、暂停、恢复、取消及读取当前计数，初始化后自动启动。
- 回前台时补偿后台遗漏的回调，支持逐次补发或仅回调最新计数。
- 保留前后台切换前的触发节奏；手动暂停期间不计数，恢复后等待完整间隔。
- 支持 RunLoop common modes，避免滚动交互影响定时器触发。

## 重要组成

- **`CatchUpTimer`**：计时与控制入口，管理计数、触发时间和生命周期补偿。
- **`MissedResponsePolicy`**：遗漏回调策略，提供 `replayAll` 和 `latestOnly`。
- **`ResponseHandler`**：接收累计计数的回调；仅最新计数策略下，计数可以跳跃。

## 测试入口

[CatchUpTimerDemo](https://github.com/Howard-Zjun/CatchUpTimerDemo)

后台期间不持续执行回调，遗漏回调在回前台时补偿。
