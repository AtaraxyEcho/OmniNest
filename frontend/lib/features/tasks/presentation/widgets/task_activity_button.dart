import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/core/widgets/anchored_popover.dart';
import 'package:omninest/core/widgets/hover_scale.dart';
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/presentation/pages/tasks_page.dart';

/// 桌面与 Web 顶栏的后台任务入口。
///
/// 任务是瞬态运行队列而非常驻收件箱，因此入口只在存在进行中或失败任务时
/// 出现，点开为紧凑面板并复用 [TasksPage] 的嵌入式列表，不另造任务视图。
/// 移动端仍由壳层「通知与任务」双 tab 页承载同一组状态。
class TaskActivityButton extends ConsumerStatefulWidget {
  const TaskActivityButton({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  ConsumerState<TaskActivityButton> createState() => _TaskActivityButtonState();
}

class _TaskActivityButtonState extends ConsumerState<TaskActivityButton> {
  final AnchoredPopover _popover = AnchoredPopover();

  @override
  void dispose() {
    // 浮层由本实例创建，入口随顶栏卸载时必须自行关闭，不能走 ref 查找。
    _popover.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(activeTaskSummaryProvider).asData?.value;
    final activeCount = summary?.activeCount ?? 0;
    final failedCount = summary?.failedCount ?? 0;
    if (activeCount == 0 && failedCount == 0) {
      return const SizedBox.shrink();
    }
    final colors = context.globalColors;
    return HoverScale(
      child: Builder(
        builder:
            (anchorContext) => IconButton(
              tooltip: AppLocalizations.of(context).tasksTitle,
              onPressed: () => _popover.open(anchorContext, _buildPanel),
              // 悬停反馈统一由 HoverScale 缩放承担，屏蔽默认置色蒙层。
              hoverColor: Colors.transparent,
              icon: Badge(
                isLabelVisible: true,
                backgroundColor:
                    failedCount > 0 ? colors.error : colors.primaryContainer,
                label: Text(
                  failedCount > 0
                      ? '$failedCount'
                      : (activeCount > 99 ? '99+' : '$activeCount'),
                  style: TextStyle(
                    // ignore: font_size_whitelist
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: failedCount > 0 ? colors.onError : colors.onSurface,
                  ),
                ),
                child: Icon(
                  Icons.pending_actions_rounded,
                  size: widget.size,
                  color: widget.color,
                ),
              ),
            ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final colors = context.globalColors;
    return Material(
      elevation: 6,
      color: colors.surfaceContainerLowest,
      child: const SizedBox(
        width: 380,
        height: 420,
        child: TasksPage(embedded: true),
      ),
    );
  }
}
