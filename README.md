# ai_todo

基于 **Flutter** 的本地待办与日程应用，数据保存在本机（**Hive**），支持提醒通知与 Android 状态栏常驻面板。

## 功能概览

| 模块 | 说明 |
|------|------|
| **时间线** | 按 `remindAt` 排序：已逾期 → 按日分组 → 「以后」（未设提醒）；左侧时间轴 + 右侧卡片 |
| **日历** | 日历视图与事件展示 |
| **班表** | 排班相关视图 |
| **待办** | 列表、优先级、子任务、筛选；点按弹出快捷操作（完成 / 修改 / 取消，含备注与提醒时间摘要） |
| **设置** | 底部导航「标签页」显隐；常驻通知面板样式与开关；提醒响铃模式；开机自启；完成提示音等 |

### 待办与提醒

- 提醒时间支持 **时间点 / 时间段 / 全天**，以及 **重复规则**（每天 / 每周 / 每月 / 每年），并与本地通知调度联动。
- 已移除「截止时间」字段，逾期与排序以 **提醒时间** 为准。

### 通知（Android 为主）

- 使用 `flutter_local_notifications`，渠道在原生侧注册，以兼容部分 ROM 对铃声、震动、锁屏展示的默认策略。
- **常驻面板**：可选开启，在通知栏显示进度与快捷「添加」；支持简洁 / 详细样式。
- 点击提醒通知可 **深链** 打开应用并定位待办。

### iOS / macOS

- 常驻通知面板等能力以 **Android** 为主；其它平台仍可正常使用待办与本地通知（能力因系统而异）。

## 环境要求

- Flutter SDK（见 `pubspec.yaml` 中 `environment.sdk`）
- Xcode（仅构建 iOS/macOS 时需要）
- Android Studio / SDK（构建 Android 时需要）

## 运行

```bash
flutter pub get
flutter run
```

## 构建

```bash
# Android
flutter build apk
# 或
flutter build appbundle

# iOS（需在 macOS 上）
flutter build ios
```

## 项目结构（简要）

- `lib/main.dart` — 入口：Hive、通知初始化、常驻面板
- `lib/main_page.dart` — 主导航与 Tab
- `lib/timeline_page.dart` — 时间线
- `lib/todo_page.dart` — 待办列表
- `lib/settings_page.dart` — 设置
- `lib/services/` — Hive、通知、原生偏好同步等
- `lib/widgets/` — 编辑器底栏、时间选择弹窗、快捷操作弹窗等
- `android/` — Kotlin：`MainActivity`（渠道、完成提示音等）、`BootReceiver` 等

## 许可

本项目以 [MIT License](LICENSE) 发布：可自由使用、复制、修改、合并、出版、分发、再许可和/或销售，仅需保留版权声明与许可全文（详见 `LICENSE`）。
