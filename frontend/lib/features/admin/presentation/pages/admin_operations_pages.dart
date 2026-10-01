import 'package:omninest/core/widgets/workstation_pagination_bar.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/domain/admin_paging.dart';
import 'package:omninest/features/admin/domain/admin_user.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_common_widgets.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_permission_tree.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_redesign_components.dart';

import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_management_models.dart';
import 'package:omninest/core/utils/status_labels.dart';
import 'package:omninest/features/video/presentation/widgets/movie_management.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_list_components.dart';
import 'package:omninest/features/admin/application/admin_log_csv.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';
part 'admin_operations_logs_tasks.dart';
part 'admin_operations_task_dialogs.dart';
part 'admin_operations_logs_center.dart';
part 'admin_operations_log_dialogs.dart';
part 'admin_operations_roles.dart';
part 'admin_operations_roles_config.dart';
part 'admin_operations_config_dialogs.dart';
part 'admin_operations_config_labels.dart';
part 'admin_operations_storage.dart';
part 'admin_operations_storage_mounts.dart';
part 'admin_operations_external_storage.dart';
part 'admin_operations_library.dart';
part 'admin_operations_sessions.dart';

// ── 详情弹窗共享组件 ──────────────────────────────────────────────────

/// 页面入场动画包装器 — 给定 children 列表，自动施加交错 fade+slide 入场。
/// 角色管理与存储分区页面共用。
class _PageEntrance extends StatefulWidget {
  const _PageEntrance({required this.children});

  final List<Widget> children;

  @override
  State<_PageEntrance> createState() => _PageEntranceState();
}

class _PageEntranceState extends State<_PageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: MotionToken.stagger, vsync: this)
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < widget.children.length; i++)
          _buildAnimated(i, widget.children[i]),
      ],
    );
  }

  Widget _buildAnimated(int index, Widget child) {
    final total = widget.children.length;
    final start = (index / total).clamp(0.0, 0.8);
    final end = (start + 0.5).clamp(0.0, 1.0);
    final curve = CurvedAnimation(
      parent: _ctrl,
      curve: Interval(start, end, curve: MotionToken.curve),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: MotionToken.slideContent,
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }
}

/// 筛选栏等宽小标前缀：置于筛选下拉之前的 mono 标签，对齐样板中
/// “操作类型: / 留存周期:” 的行内标签形态。
class _FilterPrefixLabel extends StatelessWidget {
  const _FilterPrefixLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      '$label:',
      style: TextStyle(
        fontFamily: AppTypography.monoFamily,
        fontFamilyFallback: AppTypography.monoFamilyFallback,
        fontSize: AppTypography.labelSmall,
        height: 14 / 11,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

/// 等宽代码徽标：细线描边小底色容器 + mono 编码（角色编码、模块编码、
/// Provider 编码等技术标识），对齐样板中的 code 徽标形态。
class _MonoCodeBadge extends StatelessWidget {
  const _MonoCodeBadge(this.code);

  final String code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        code,
        style: TextStyle(
          fontFamily: AppTypography.monoFamily,
          fontFamilyFallback: AppTypography.monoFamilyFallback,
          fontSize: AppTypography.labelSmall,
          height: 14 / 11,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w500,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}

/// 列表页批量操作条：已选数量、取消选择与主操作按钮。
/// 任务队列与活跃会话两页共用；可选次操作按钮（如任务批量取消）。
class _AdminBatchBar extends StatelessWidget {
  const _AdminBatchBar({
    required this.count,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    required this.onClear,
    this.secondaryActionLabel,
    this.secondaryActionIcon,
    this.onSecondaryAction,
  });

  final int count;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;
  final VoidCallback onClear;

  /// 次操作：与主操作并存（如“批量取消”与“批量重试”），为空时不渲染。
  final String? secondaryActionLabel;
  final IconData? secondaryActionIcon;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Text(
          l10n.adminListSelectedCount('$count'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const Spacer(),
        TextButton(
          onPressed: onClear,
          child: Text(l10n.adminBatchClearSelection),
        ),
        if (secondaryActionLabel != null && onSecondaryAction != null) ...[
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: onSecondaryAction,
            icon: Icon(secondaryActionIcon ?? Icons.close_rounded, size: 18),
            label: Text(secondaryActionLabel!),
          ),
        ],
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: onAction,
          icon: Icon(actionIcon, size: 18),
          label: Text(actionLabel),
        ),
      ],
    );
  }
}

/// 弹窗键值行：左侧固定宽度标签 + 右侧自适应值（可选等宽字体或自绘控件）。
class _DetailKeyValueRow extends StatelessWidget {
  const _DetailKeyValueRow({
    required this.label,
    this.value,
    this.child,
    this.mono = false,
  });

  final String label;

  /// 纯文本值；传入 [child] 时忽略。
  final String? value;

  /// 自定义值控件（状态标签、警示块等）。
  final Widget? child;

  /// 值是否使用等宽字体（ID、队列名、时间戳等技术值）。
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final valueStyle =
        mono
            ? TextStyle(
              fontFamily: AppTypography.monoFamily,
              fontFamilyFallback: AppTypography.monoFamilyFallback,
              fontSize: AppTypography.bodySmall,
              height: 16 / 12,
              color: scheme.onSurface,
            )
            : Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurface);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: child ?? Text(value ?? '-', style: valueStyle)),
        ],
      ),
    );
  }
}

/// 变更快照色块语义：旧值绯红、新值翠绿。
enum _SnapshotTone { oldValue, newValue }

/// 变更快照值块：语义色细线框 + 等宽内容，用于审计详情的旧值/新值比对。
class _SnapshotValueBlock extends StatelessWidget {
  const _SnapshotValueBlock({
    required this.label,
    required this.text,
    required this.tone,
  });

  final String label;
  final String text;
  final _SnapshotTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color =
        tone == _SnapshotTone.oldValue
            ? scheme.error
            : context.adminColors.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTypography.monoFamily,
              fontFamilyFallback: AppTypography.monoFamilyFallback,
              fontSize: AppTypography.labelSmall,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text.isEmpty ? '-' : text,
            style: TextStyle(
              fontFamily: AppTypography.monoFamily,
              fontFamilyFallback: AppTypography.monoFamilyFallback,
              fontSize: AppTypography.bodySmall,
              height: 16 / 12,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// 负载值展示：null 显示 '-'，字符串原样，其余结构 JSON 缩进序列化，
/// 失败回退 toString。
String _formatPayloadValue(Object? value) {
  if (value == null) {
    return '-';
  }
  if (value is String) {
    return value;
  }
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } on Object {
    return value.toString();
  }
}

/// 键排序后的缩进 JSON，用于审计详情的原始负载块。
String _prettyPayloadJson(Map<String, Object> payload) {
  final sorted = Map<String, Object>.fromEntries(
    payload.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
  try {
    return const JsonEncoder.withIndent('  ').convert(sorted);
  } on Object {
    return payload.toString();
  }
}

/// 清理确认弹窗：目标类型 + 保留期 + 异步预估条数（loading 转圈、失败
/// 显示 '-' 且不阻塞清理）+ 物理删除红色警示 + 可选补充说明。
/// 预估 Provider 为 autoDispose family，弹窗关闭即释放。
class _CleanupConfirmDialog extends ConsumerWidget {
  const _CleanupConfirmDialog({
    required this.targetLabel,
    required this.retentionDays,
    required this.kind,
    this.hintText,
    this.showExportHint = false,
  });

  final String targetLabel;
  final int retentionDays;
  final AdminCleanupPreviewKind kind;

  /// 补充说明（如“在线会话不受影响”）。
  final String? hintText;

  /// 是否展示“建议先导出 CSV”提示。
  final bool showExportHint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final preview = ref.watch(
      adminCleanupPreviewProvider((kind: kind, retentionDays: retentionDays)),
    );
    final Widget previewValue;
    if (preview.isLoading) {
      previewValue = const SizedBox.square(
        dimension: 14,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      );
    } else {
      previewValue = Text(
        preview.hasError ? '-' : '${preview.value}',
        style: TextStyle(
          fontFamily: AppTypography.monoFamily,
          fontFamilyFallback: AppTypography.monoFamilyFallback,
          fontSize: AppTypography.bodyMedium,
          color: scheme.onSurface,
        ),
      );
    }
    return WorkstationDialogFrame(
      title: l10n.adminCleanupConfirmTitle,
      destructive: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailKeyValueRow(
            label: l10n.adminCleanupTarget,
            value: targetLabel,
          ),
          _DetailKeyValueRow(
            label: l10n.adminCleanupRetention,
            value: l10n.adminRetentionDays('$retentionDays'),
          ),
          _DetailKeyValueRow(
            label: l10n.adminCleanupPreviewCount,
            child: previewValue,
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: scheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.adminCleanupPhysicalWarning,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: scheme.error),
                ),
              ),
            ],
          ),
          if (showExportHint) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.file_download_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.adminCleanupExportHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (hintText != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hintText!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.coreCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.adminCleanup),
        ),
      ],
    );
  }
}
