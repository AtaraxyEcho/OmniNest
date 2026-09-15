import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
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
/// 提供最小化到托盘与退出程序两个动作，并支持勾选记住选择。
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
    return AlertDialog(
      title: Text(l10n.desktopCloseDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.desktopCloseDialogBody),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _toggleRemember(!_remember),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Checkbox(value: _remember, onChanged: _toggleRemember),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l10n.desktopCloseDialogRemember)),
                ],
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
