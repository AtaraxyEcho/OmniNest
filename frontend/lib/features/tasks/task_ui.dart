// 任务模块对外暴露的共享 UI 入口。
//
// 其他模块只从该根入口引用任务组件，避免跨 feature 直接依赖 presentation
// 目录（与 `features/notifications/notification_ui.dart` 同一约定）。
export 'package:omninest/features/tasks/presentation/widgets/task_activity_button.dart'
    show TaskActivityButton;
