import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/notifications/presentation/utils/notification_action.dart';
import 'package:omninest/features/notifications/presentation/utils/notification_type_l10n.dart';
import 'package:omninest/features/files/application/media_import_queue_controller.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

enum _NotifFilter { all, unread }

class NotificationsPanel extends ConsumerStatefulWidget {
  const NotificationsPanel({super.key});

  @override
  ConsumerState<NotificationsPanel> createState() => NotificationsPanelState();
}

class NotificationsPanelState extends ConsumerState<NotificationsPanel> {
  _NotifFilter _filter = _NotifFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(notificationControllerProvider.notifier).load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(notificationControllerProvider);
    final unread = ref.watch(unreadCountProvider);
    final controller = ref.read(notificationControllerProvider.notifier);
    final shell = ref.read(desktopShellProvider.notifier);
    final items =
        state.items
            .where((item) => _filter == _NotifFilter.all || !item.read)
            .toList();
    // 样例按 Today / Earlier 分组；没有时间戳的旧记录归入更早。
    final now = DateTime.now();
    bool isToday(NotificationDto item) {
      final created = item.createdAt;
      return created.year == now.year &&
          created.month == now.month &&
          created.day == now.day;
    }

    final rows = <Object>[
      if (items.any(isToday)) ...[
        l10n.desktopNotifToday,
        ...items.where(isToday),
      ],
      if (items.any((item) => !isToday(item))) ...[
        l10n.desktopNotifEarlier,
        ...items.where((item) => !isToday(item)),
      ],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.desktopNotifications,
                    style: DesktopType.cardTitle(skin.text),
                  ),
                  Text(
                    l10n.desktopUnreadSummary(unread),
                    style: DesktopType.caption(skin.text3),
                  ),
                ],
              ),
            ),
            DesktopLink(
              label: l10n.desktopMarkAllRead,
              trailing: false,
              onPressed:
                  unread == 0
                      ? null
                      : () {
                        controller.markAllRead();
                        showDesktopToast(context, l10n.desktopToastAllRead);
                      },
            ),
          ],
        ),
        const SizedBox(height: 12),
        DesktopSeg<_NotifFilter>(
          options: _NotifFilter.values,
          value: _filter,
          small: true,
          labelOf:
              (value) =>
                  value == _NotifFilter.all
                      ? l10n.desktopFilterAll
                      : l10n.desktopFilterUnread,
          onChanged: (value) => setState(() => _filter = value),
        ),
        const SizedBox(height: 8),
        Flexible(
          child:
              items.isEmpty
                  ? DesktopEmpty(
                    message: l10n.desktopNothingUnread,
                    icon: DesktopIcons.check,
                  )
                  : ListView.builder(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      if (row is String) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                          child: Text(
                            row.toUpperCase(),
                            style: DesktopType.eyebrow(skin.text3),
                          ),
                        );
                      }
                      final item = row as NotificationDto;
                      final action = notificationActionFor(item, l10n);
                      final progress = _notifProgress(item);
                      final title = _notificationTitle(item, l10n);
                      final message = _notificationMessage(item, l10n);
                      return DesktopHover(
                        builder:
                            (context, hovered) => GestureDetector(
                              // 样例 `Shell.tsx:129`：点行只标已读，不关面板也不
                              // 跳转；跳转是行内那条独立的动作链接。
                              onTap: () => controller.markRead(item.id),
                              behavior: HitTestBehavior.opaque,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 11,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          hovered
                                              ? skin.raise
                                              : Colors.transparent,
                                      borderRadius: BorderRadius.circular(
                                        DesktopMetrics.radius,
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: skin.raise2,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Icon(
                                            notificationTypeIcon(item.type),
                                            size: 16,
                                            color:
                                                item.read
                                                    ? skin.text3
                                                    : skin.accent,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                // 样例 `.notif strong`：13 / 600。
                                                style: DesktopType.dense(
                                                  item.read
                                                      ? skin.text2
                                                      : skin.text,
                                                ).copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              if (message != null)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 2,
                                                      ),
                                                  child: Text(
                                                    message,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    // 样例 `.notif p`：12.5 / text2。
                                                    style:
                                                        DesktopType.secondary(
                                                          skin.text2,
                                                        ),
                                                  ),
                                                ),
                                              if (progress != null)
                                                _NotifProgress(value: progress),
                                              if (action != null)
                                                Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: DesktopLink(
                                                    label: action.label,
                                                    onPressed: () {
                                                      controller.markRead(
                                                        item.id,
                                                      );
                                                      shell.setPanel(
                                                        DesktopPanel.none,
                                                      );
                                                      _openNotifAction(
                                                        context,
                                                        action.route,
                                                      );
                                                    },
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // 样例 `.notif time`：11 / text3 的右列时间。
                                        Text(
                                          _notifTime(context, item.createdAt),
                                          style: DesktopType.caption(
                                            skin.text3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // 样例 `.notif.unread::before`：行左缘外侧的
                                  // 6px 强调点，不占列宽。
                                  if (!item.read)
                                    Positioned(
                                      left: -2,
                                      top: 22,
                                      child: Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: skin.accent,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: skin.accentWash(0.6),
                                              blurRadius: 10,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                      );
                    },
                  ),
        ),
        const SizedBox(height: 8),
        Container(height: 1, color: skin.line),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                child: DesktopLink(
                  label: l10n.desktopNotificationSettings,
                  icon: DesktopIcons.settings,
                  trailing: false,
                  onPressed: () {
                    shell.setPanel(DesktopPanel.none);
                    desktopGo(context, DesktopRoutes.settingsNotifications);
                  },
                ),
              ),
              DesktopLink(
                label: l10n.desktopClearAll,
                trailing: false,
                // 样例 `Shell.tsx:139`：Clear all 是「全部标已读 + toast」的伪清空，
                // 真的删记录要走通知中心。桌面不再单独开一条删除路径。
                onPressed:
                    unread == 0
                        ? null
                        : () {
                          controller.markAllRead();
                          showDesktopToast(
                            context,
                            l10n.desktopToastNotificationsCleared,
                          );
                        },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 样例 `.notif time`：`HH:mm`，跟随界面语言。
String _notifTime(BuildContext context, DateTime createdAt) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.Hm(locale).format(createdAt);
}

String _notificationTitle(NotificationDto item, AppLocalizations l10n) {
  final title = item.title?.trim();
  if (title != null && title.isNotEmpty) {
    return title;
  }
  final typeLabel = notificationTypeLabel(item.type, l10n).trim();
  // 旧记录可能只有 id/时间而没有 type/title。通知行仍要保留可读的
  // 标题高度，否则在桌面面板里只剩图标和时间，和样例的三列通知行不符。
  return typeLabel.isNotEmpty ? typeLabel : l10n.desktopNotifications;
}

String? _notificationMessage(NotificationDto item, AppLocalizations l10n) {
  final message = item.message?.trim();
  if (message != null && message.isNotEmpty) {
    return message;
  }
  final synthesized = synthesizedNotificationText(item, l10n);
  if (synthesized != null && synthesized.isNotEmpty) {
    return synthesized;
  }
  final description = notificationTypeDescription(item.type, l10n);
  return description?.isNotEmpty == true ? description : null;
}

/// 通知行的进度值：0–1，取不到就是 null。
///
/// 样例 `Shell.tsx:112` 的 `n.progress` 只对带进度的通知渲染一条
/// `.mini-prog`；样例数据是本地假数据（`setProg` 每 700ms +1），我们这边
/// 没有对应的后端字段，因此改读 `metadata.progress`（兼容 0–1 与百分数）。
/// 拿不到值就不画——伪造一个自己会走的进度条比不画更糟。
double? _notifProgress(NotificationDto item) {
  final raw = item.metadata['progress'];
  final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
  if (value == null || !value.isFinite || value <= 0) {
    return null;
  }
  return (value > 1 ? value / 100 : value).clamp(0, 1);
}

/// 通知动作跳转：壳层 chrome 在 Router 之上，必须经 [DesktopRouterScope]。
///
/// 四空间分支要换掉整条栈（`go`），其余根级路由压栈保留来路（`push`），
/// 与 [navigateNotificationAction] 的判定保持一致。
void _openNotifAction(BuildContext context, String route) {
  const shellBranches = <String>{'/portal', '/library', '/reader', '/files'};
  if (shellBranches.contains(route.split('?').first)) {
    desktopGo(context, route);
    return;
  }
  desktopPush(context, route);
}

/// 样例 `.mini-prog`：4px 轨道 + accent 进度条 + 右下角百分比。
class _NotifProgress extends StatelessWidget {
  const _NotifProgress({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 4,
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: skin.raise3)),
                  FractionallySizedBox(
                    widthFactor: value,
                    child: ColoredBox(color: skin.accent),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${(value * 100).round()}%',
              style: DesktopType.caption(skin.text3),
            ),
          ),
        ],
      ),
    );
  }
}

class TasksPanel extends ConsumerStatefulWidget {
  const TasksPanel({super.key});

  @override
  ConsumerState<TasksPanel> createState() => TasksPanelState();
}

class TasksPanelState extends ConsumerState<TasksPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(taskListProvider.notifier).load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final tasks = ref.watch(taskListProvider);
    final mediaImports = ref.watch(mediaImportQueueProvider);
    final shell = ref.read(desktopShellProvider.notifier);
    // 与后端角标同口径：只算 RUNNING + QUEUED（样例 `Shell.tsx:147`）。
    // RETRY_WAIT 仍会出现在下面的列表里，只是不计数。
    final active =
        tasks.where((task) => task.isRunning || task.isQueued).length +
        mediaImports.where((task) => task.isActive).length;
    final failed =
        tasks.where((task) => task.isFailed).length +
        mediaImports.where((task) => task.isFailed).length;
    final visibleMediaImports = mediaImports.reversed.take(8).toList();
    final totalRows = visibleMediaImports.length + tasks.length;
    final visibleTaskCount = totalRows > 8 ? 8 : totalRows;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.desktopBackgroundTasks,
                    style: DesktopType.cardTitle(skin.text),
                  ),
                  Text(
                    l10n.desktopTasksSummary(active, failed),
                    style: DesktopType.caption(skin.text3),
                  ),
                ],
              ),
            ),
            DesktopLink(
              label: l10n.desktopAllTasks,
              onPressed: () {
                shell.setPanel(DesktopPanel.none);
                desktopGo(context, DesktopRoutes.adminOperations);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Flexible(
          child:
              tasks.isEmpty && mediaImports.isEmpty
                  ? DesktopEmpty(
                    message: l10n.desktopNothingRunning,
                    icon: DesktopIcons.check,
                  )
                  : ListView.builder(
                    shrinkWrap: true,
                    itemCount: visibleTaskCount,
                    itemBuilder:
                        (context, index) =>
                            index < visibleMediaImports.length
                                ? DesktopMediaImportTaskRow(
                                  task: visibleMediaImports[index],
                                )
                                : DesktopTaskRow(
                                  task:
                                      tasks[index - visibleMediaImports.length],
                                ),
                  ),
        ),
      ],
    );
  }
}

class DesktopMediaImportTaskRow extends ConsumerWidget {
  const DesktopMediaImportTaskRow({required this.task, super.key});

  final MediaImportQueueTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final tone = switch (task.status) {
      MediaImportQueueStatus.failed => skin.bad,
      MediaImportQueueStatus.completed => skin.ok,
      MediaImportQueueStatus.uploading ||
      MediaImportQueueStatus.processing => skin.accent,
      MediaImportQueueStatus.queued ||
      MediaImportQueueStatus.cancelled => skin.text3,
    };
    final label = switch (task.status) {
      MediaImportQueueStatus.queued => l10n.desktopTaskStatusQueued,
      MediaImportQueueStatus.uploading ||
      MediaImportQueueStatus.processing => l10n.desktopTaskStatusRunning,
      MediaImportQueueStatus.completed => l10n.desktopTaskStatusCompleted,
      MediaImportQueueStatus.failed => l10n.desktopTaskStatusFailed,
      MediaImportQueueStatus.cancelled => l10n.desktopTaskStatusCancelled,
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: skin.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              task.status == MediaImportQueueStatus.completed
                  ? DesktopIcons.check
                  : task.status == MediaImportQueueStatus.failed
                  ? DesktopIcons.info
                  : DesktopIcons.download,
              size: 15,
              color: tone,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.rowTitle(skin.text),
                ),
                Text(label, style: DesktopType.caption(skin.text3)),
                if (task.status == MediaImportQueueStatus.uploading ||
                    task.status == MediaImportQueueStatus.processing)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: DesktopProgress(fraction: task.progress),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          DesktopChip(label, tone: tone),
          if (task.canRetry) ...[
            const SizedBox(width: 8),
            DesktopButton(
              label: l10n.desktopRetry,
              icon: DesktopIcons.retry,
              variant: DesktopButtonVariant.soft,
              onPressed:
                  () => ref
                      .read(mediaImportQueueProvider.notifier)
                      .retry(task.id),
            ),
          ] else if (task.isActive) ...[
            const SizedBox(width: 8),
            DesktopButton.iconOnly(
              icon: DesktopIcons.close,
              tooltip: l10n.desktopCancel,
              onPressed:
                  () => ref
                      .read(mediaImportQueueProvider.notifier)
                      .cancel(task.id),
            ),
          ],
        ],
      ),
    );
  }
}

/// 任务行（样例 `TaskRow`），面板与管理台共用同一形态。
class DesktopTaskRow extends ConsumerWidget {
  const DesktopTaskRow({required this.task, super.key});

  final TaskRecord task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final tone =
        task.isFailed
            ? skin.bad
            : task.isCompleted
            ? skin.ok
            : task.isRunning
            ? skin.accent
            : skin.text3;
    final label =
        task.isFailed
            ? l10n.desktopTaskStatusFailed
            : task.isCompleted
            ? l10n.desktopTaskStatusCompleted
            : task.isRunning
            ? l10n.desktopTaskStatusRunning
            : task.isCancelled
            ? l10n.desktopTaskStatusCancelled
            : l10n.desktopTaskStatusQueued;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: skin.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              task.isCompleted
                  ? DesktopIcons.check
                  : task.isFailed
                  ? DesktopIcons.info
                  : DesktopIcons.clock,
              size: 15,
              color: tone,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  task.result?.trim().isNotEmpty == true
                      ? task.result!
                      : task.taskType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.rowTitle(skin.text),
                ),
                Text(
                  task.errorMessage?.trim().isNotEmpty == true
                      ? task.errorMessage!
                      : task.taskType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.caption(skin.text3),
                ),
                if (task.isRunning)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: DesktopProgress(fraction: task.progress / 100),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          DesktopChip(label, tone: tone),
          if (task.canRetry) ...[
            const SizedBox(width: 8),
            DesktopButton(
              label: l10n.desktopRetry,
              variant: DesktopButtonVariant.soft,
              onPressed:
                  () => ref.read(taskListProvider.notifier).retry(task.id),
            ),
          ],
        ],
      ),
    );
  }
}
