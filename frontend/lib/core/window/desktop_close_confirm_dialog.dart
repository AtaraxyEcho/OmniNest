import 'package:material_ui/material_ui.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/window/desktop_close_action.dart';

/// 弹出关闭确认窗，返回用户决策；null 表示取消，保持窗口现状。
///
/// 统一走新版桌面弹层（[showDesktopDialog] + [DesktopDialog]），依赖
/// `Theme.of(context).extension<DesktopSkin>()`（登录前由 `DesktopThemeScope`
/// 提供、登录后由 `DesktopShellHost` 提供），保证未登录/首启页关窗也能正常弹出。
Future<DesktopCloseDecision?> showDesktopCloseConfirmDialog(
  BuildContext context,
) {
  return showDesktopDialog<DesktopCloseDecision>(
    context,
    builder: (dialogContext) => const DesktopCloseConfirmDialog(),
  );
}

/// 首次关闭主窗口的确认弹窗。
///
/// 头部为图标徽章 + 标题，正文说明最小化到托盘的语义，记住选择项放在
/// 淡染容器内成组展示，动作按钮按"取消 / 最小化到托盘 / 退出程序"排列。
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
    closeDesktopModal(
      context,
      DesktopCloseDecision(action: action, remember: _remember),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin =
        Theme.of(context).extension<DesktopSkin>() ?? DesktopSkin.of(context);
    return DesktopDialog(
      title: l10n.desktopCloseDialogTitle,
      width: 440,
      lead: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: skin.accentWash(0.14),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: skin.accentWash(0.26)),
        ),
        child: Icon(
          Icons.power_settings_new_rounded,
          size: 19,
          color: skin.accent,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.desktopCloseDialogBody,
            style: DesktopType.body(skin.text2).copyWith(height: 1.55),
          ),
          const SizedBox(height: 16),
          DesktopHover(
            builder:
                (context, hovered) => GestureDetector(
                  onTap: () => _toggleRemember(!_remember),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: hovered ? skin.raise2 : skin.raise,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: skin.line),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: _remember,
                            onChanged: _toggleRemember,
                            fillColor: WidgetStateProperty.resolveWith<Color?>(
                              (states) =>
                                  states.contains(WidgetState.selected)
                                      ? skin.accent
                                      : null,
                            ),
                            checkColor: skin.accentInk,
                            side: BorderSide(color: skin.line2, width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l10n.desktopCloseDialogRemember,
                            style: DesktopType.dense(skin.text),
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
        DesktopButton(
          label: l10n.coreCancel,
          variant: DesktopButtonVariant.ghost,
          onPressed: () => closeDesktopModal(context),
        ),
        DesktopButton(
          label: l10n.desktopCloseDialogMinimize,
          variant: DesktopButtonVariant.soft,
          onPressed: () => _submit(DesktopCloseAction.minimizeToTray),
        ),
        DesktopButton(
          label: l10n.desktopCloseDialogExit,
          variant: DesktopButtonVariant.primary,
          onPressed: () => _submit(DesktopCloseAction.exitApp),
        ),
      ],
    );
  }
}
