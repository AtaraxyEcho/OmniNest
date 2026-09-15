import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/core/window/desktop_close_action.dart';

/// 弹出关闭确认窗，返回用户决策；null 表示取消，保持窗口现状。
Future<DesktopCloseDecision?> showDesktopCloseConfirmDialog(
  BuildContext context,
) {
  return showDialog<DesktopCloseDecision>(
    context: context,
    builder: (dialogContext) => const DesktopCloseConfirmDialog(),
  );
}

/// 首次关闭主窗口的确认弹窗。
///
/// 头部为图标徽章 + 标题，正文说明最小化到托盘的语义，记住选择项放在
/// 淡染容器内成组展示，动作按钮按"最小化到托盘 / 退出程序 / 取消"排列。
class DesktopCloseConfirmDialog extends StatefulWidget {
  const DesktopCloseConfirmDialog({super.key});

  @override
  State<DesktopCloseConfirmDialog> createState() =>
      _DesktopCloseConfirmDialogState();
}

class _DesktopCloseConfirmDialogState extends State<DesktopCloseConfirmDialog> {
  bool _remember = false;

  void _toggleRemember(bool? value) {
    setState(() => _remember = value ?? false);
  }

  void _submit(DesktopCloseAction action) {
    Navigator.of(
      context,
    ).pop(DesktopCloseDecision(action: action, remember: _remember));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.globalColors;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.power_settings_new_rounded,
                  size: 20,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.desktopCloseDialogTitle,
                  style: TextStyle(
                    fontSize: AppTypography.titleLarge,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            l10n.desktopCloseDialogBody,
            style: TextStyle(
              fontSize: AppTypography.bodyMedium,
              height: 1.5,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Material(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _toggleRemember(!_remember),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 12, 2),
                child: Row(
                  children: [
                    Checkbox(value: _remember, onChanged: _toggleRemember),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.desktopCloseDialogRemember,
                        style: TextStyle(
                          fontSize: AppTypography.bodyMedium,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        FilledButton.tonal(
          onPressed: () => _submit(DesktopCloseAction.minimizeToTray),
          child: Text(l10n.desktopCloseDialogMinimize),
        ),
        FilledButton(
          onPressed: () => _submit(DesktopCloseAction.exitApp),
          child: Text(l10n.desktopCloseDialogExit),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.coreCancel),
        ),
      ],
    );
  }
}
