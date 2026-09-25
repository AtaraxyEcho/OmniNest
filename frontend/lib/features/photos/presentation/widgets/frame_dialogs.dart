import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_common_widgets.dart';
import 'package:omninest/app/theme/severity_colors.dart';

/// Frame 风格对话框：Photos 模块统一的最小化弹窗（searchFill 底、
/// 12px 圆角、衬线标题、TextButton 动作，主操作 btnBg 底、危险操作红色）。
///
/// 模块内所有弹窗（确认 / 单行输入 / 选择 / 新建影集）统一从本文件发起，
/// 保证与 Frame 设计语言一致；字段色经 `frameColors` 随亮暗主题解析。

/// Frame 确认弹窗；确认返回 true，取消/关闭返回 false。
Future<bool> showFrameConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final colors = context.frameColors;
  final result = await showDialog<bool>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          backgroundColor: colors.searchFill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: _frameDialogTitle(context, title),
          content: Text(
            body,
            style: TextStyle(
              color: colors.sub,
              fontSize: AppTypography.bodyLarge,
            ),
          ),
          actions: [
            _frameCancelAction(ctx, context),
            FrameDialogActionButton(
              label: confirmLabel,
              destructive: destructive,
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
  );
  return result ?? false;
}

/// Frame 单行输入弹窗；返回输入文本（已 trim），取消返回 null。
Future<String?> showFramePromptDialog(
  BuildContext context, {
  required String title,
  String? hint,
  bool obscureText = false,
  required String confirmLabel,
}) {
  return showDialog<String>(
    context: context,
    builder:
        (ctx) => PhotoDialogTextField(
          builder:
              (ctx, controller) => AlertDialog(
                backgroundColor: context.frameColors.searchFill,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: _frameDialogTitle(ctx, title),
                content: TextField(
                  controller: controller,
                  autofocus: true,
                  obscureText: obscureText,
                  style: TextStyle(
                    color: ctx.frameColors.ink,
                    fontSize: AppTypography.bodyLarge,
                  ),
                  decoration: _frameFieldDecoration(ctx, hint: hint),
                ),
                actions: [
                  _frameCancelAction(ctx, context),
                  FrameDialogActionButton(
                    label: confirmLabel,
                    onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                  ),
                ],
              ),
        ),
  );
}

/// Frame 选择弹窗的单个选项。
class FrameChoice<T> {
  const FrameChoice({required this.value, required this.title, this.subtitle});

  final T value;
  final String title;

  /// 次要说明（如相册照片数）；为空时不渲染。
  final String? subtitle;
}

/// Frame 选择弹窗；返回选中项的值，取消返回 null，无选项时展示 [emptyMessage]。
Future<T?> showFrameChoiceDialog<T>(
  BuildContext context, {
  required String title,
  required List<FrameChoice<T>> choices,
  String? emptyMessage,
}) {
  final colors = context.frameColors;
  final l10n = AppLocalizations.of(context);
  return showDialog<T>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          backgroundColor: colors.searchFill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: _frameDialogTitle(ctx, title),
          content:
              choices.isEmpty
                  ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      emptyMessage ?? l10n.photosNoAlbums,
                      style: TextStyle(
                        color: colors.sub,
                        fontSize: AppTypography.bodyMedium,
                      ),
                    ),
                  )
                  : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final choice in choices)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  hoverColor: colors.hover,
                                  onTap: () => Navigator.pop(ctx, choice.value),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          choice.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: colors.ink,
                                            fontSize: AppTypography.bodyLarge,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (choice.subtitle != null)
                                          Text(
                                            choice.subtitle!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: colors.muted,
                                              fontSize: AppTypography.bodySmall,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          actions: [_frameCancelAction(ctx, context)],
        ),
  );
}

/// Frame 新建影集弹窗；返回 (名称, 描述)，取消返回 null，名称为空不提交。
Future<(String, String)?> showFrameNewAlbumDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showDialog<(String, String)>(
    context: context,
    builder:
        (ctx) => PhotoDialogTextField(
          builder:
              (ctx, nameController) => PhotoDialogTextField(
                builder:
                    (ctx, descController) => AlertDialog(
                      backgroundColor: ctx.frameColors.searchFill,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      title: _frameDialogTitle(ctx, l10n.photosNewAlbum),
                      // 双输入框在键盘弹出时可能超出可用高，滚动兜底。
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: nameController,
                              autofocus: true,
                              style: TextStyle(
                                color: ctx.frameColors.ink,
                                fontSize: AppTypography.bodyLarge,
                              ),
                              decoration: _frameFieldDecoration(
                                ctx,
                                hint: l10n.photosAlbumNameHint,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: descController,
                              style: TextStyle(
                                color: ctx.frameColors.ink,
                                fontSize: AppTypography.bodyLarge,
                              ),
                              decoration: _frameFieldDecoration(
                                ctx,
                                hint: l10n.photosAlbumDescriptionHint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        _frameCancelAction(ctx, context),
                        FrameDialogActionButton(
                          label: l10n.photosCreate,
                          onPressed: () {
                            final name = nameController.text.trim();
                            if (name.isEmpty) return;
                            Navigator.pop(ctx, (
                              name,
                              descController.text.trim(),
                            ));
                          },
                        ),
                      ],
                    ),
              ),
        ),
  );
}

/// Frame 弹窗主操作按钮：btnBg 底圆角 8；[destructive] 时红色底。
class FrameDialogActionButton extends StatelessWidget {
  const FrameDialogActionButton({
    required this.label,
    required this.onPressed,
    this.destructive = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.frameColors;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: destructive ? SeverityColors.danger : colors.btnBg,
        foregroundColor: destructive ? Colors.white : colors.onBtn,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label),
    );
  }
}

Text _frameDialogTitle(BuildContext context, String title) {
  final colors = context.frameColors;
  return Text(
    title,
    style: TextStyle(
      fontFamily: FramePalette.serifFamily,
      fontFamilyFallback: FramePalette.serifFallback,
      color: colors.ink,
      fontSize: AppTypography.titleLarge,
    ),
  );
}

Widget _frameCancelAction(BuildContext ctx, BuildContext context) {
  final colors = context.frameColors;
  return TextButton(
    onPressed: () => Navigator.pop(ctx),
    child: Text(
      AppLocalizations.of(context).photosCancel,
      style: TextStyle(color: colors.sub),
    ),
  );
}

InputDecoration _frameFieldDecoration(BuildContext context, {String? hint}) {
  final colors = context.frameColors;
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: colors.muted),
    filled: true,
    fillColor: colors.hover,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colors.accent),
    ),
  );
}
