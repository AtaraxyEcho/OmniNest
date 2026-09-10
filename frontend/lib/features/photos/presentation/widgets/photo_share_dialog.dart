import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/photos/domain/photo_share_link.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_dialogs.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_common_widgets.dart';

/// 照片/相册分享管理对话框：密码 + 有效期 + 现有链接管理（Frame 极简风格）。
///
/// 返回 (密码, 有效期选项)；取消返回 null。创建与撤销由调用方通过回调执行，
/// 撤销成功后对话框关闭。
Future<(String, String)?> showPhotoShareDialog(
  BuildContext context, {
  required String title,
  required List<PhotoShareLink> shares,
  required Future<void> Function(String shareId) onRevoke,
}) async {
  String expiryOption = 'never';

  return showDialog<(String, String)>(
    context: context,
    builder:
        (ctx) => PhotoDialogTextField(
          builder:
              (ctx, passwordController) => StatefulBuilder(
                builder:
                    (ctx, setDialogState) => AlertDialog(
                      backgroundColor: ctx.frameColors.searchFill,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      title: Text(
                        title,
                        style: TextStyle(
                          fontFamily: FramePalette.serifFamily,
                          fontFamilyFallback: FramePalette.serifFallback,
                          color: ctx.frameColors.ink,
                          fontSize: AppTypography.titleLarge,
                        ),
                      ),
                      content: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: SizedBox(
                          width: 400,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 密码字段
                              TextField(
                                controller: passwordController,
                                obscureText: true,
                                style: TextStyle(
                                  color: ctx.frameColors.ink,
                                  fontSize: AppTypography.bodyLarge,
                                ),
                                decoration: InputDecoration(
                                  hintText:
                                      AppLocalizations.of(
                                        context,
                                      ).photosSharePasswordHint,
                                  hintStyle: TextStyle(
                                    color: ctx.frameColors.muted,
                                  ),
                                  filled: true,
                                  fillColor: ctx.frameColors.hover,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: ctx.frameColors.border,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: ctx.frameColors.accent,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // 有效期
                              Text(
                                AppLocalizations.of(context).photosShareExpiry,
                                style: TextStyle(
                                  color: ctx.frameColors.sub,
                                  fontSize: AppTypography.bodySmall,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  for (final option in const [
                                    '1d',
                                    '7d',
                                    '30d',
                                    'never',
                                  ])
                                    _ExpiryChip(
                                      label: _expiryLabel(context, option),
                                      selected: expiryOption == option,
                                      onTap:
                                          () => setDialogState(
                                            () => expiryOption = option,
                                          ),
                                    ),
                                ],
                              ),
                              // 现有链接
                              if (shares.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  ).photosExistingShareLinks,
                                  style: TextStyle(
                                    color: ctx.frameColors.sub,
                                    fontSize: AppTypography.bodySmall,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...shares.map(
                                  (share) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                share.token,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: ctx.frameColors.ink,
                                                  fontSize:
                                                      AppTypography.bodyMedium,
                                                ),
                                              ),
                                              Text(
                                                AppLocalizations.of(
                                                  context,
                                                ).photosShareAccessCount(
                                                  share.accessCount,
                                                ),
                                                style: TextStyle(
                                                  color: ctx.frameColors.muted,
                                                  fontSize:
                                                      AppTypography.labelSmall,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          tooltip:
                                              AppLocalizations.of(
                                                context,
                                              ).coreDelete,
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                            color: Color(0xFFEF4444),
                                          ),
                                          onPressed: () async {
                                            try {
                                              await onRevoke(share.id);
                                              if (ctx.mounted) {
                                                Navigator.pop(ctx, null);
                                              }
                                            } on Exception catch (error) {
                                              if (ctx.mounted) {
                                                ScaffoldMessenger.of(
                                                  ctx,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      describeUserFacingError(
                                                        error,
                                                      ).displayMessage,
                                                    ),
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(
                            AppLocalizations.of(context).photosCancel,
                            style: TextStyle(color: ctx.frameColors.sub),
                          ),
                        ),
                        FrameDialogActionButton(
                          label: AppLocalizations.of(context).photosCreateLink,
                          onPressed:
                              () => Navigator.pop(ctx, (
                                passwordController.text.trim(),
                                expiryOption,
                              )),
                        ),
                      ],
                    ),
              ),
        ),
  );
}

String _expiryLabel(BuildContext context, String option) {
  final l10n = AppLocalizations.of(context);
  return switch (option) {
    '1d' => l10n.photosShareExpiry1d,
    '7d' => l10n.photosShareExpiry7d,
    '30d' => l10n.photosShareExpiry30d,
    _ => l10n.photosShareExpiryNever,
  };
}

class _ExpiryChip extends StatelessWidget {
  const _ExpiryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.frameColors;
    return Material(
      color: selected ? colors.accent.withValues(alpha: 0.12) : colors.hover,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? colors.accent : colors.border),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? colors.accent : colors.sub,
              fontSize: AppTypography.bodySmall,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// 把对话框选择的有效期换算为绝对过期时间。
DateTime? resolveShareExpiry(String expiryOption) {
  if (expiryOption == '1d') {
    return DateTime.now().add(const Duration(days: 1));
  }
  if (expiryOption == '7d') {
    return DateTime.now().add(const Duration(days: 7));
  }
  if (expiryOption == '30d') {
    return DateTime.now().add(const Duration(days: 30));
  }
  return null;
}
