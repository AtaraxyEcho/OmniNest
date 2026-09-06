import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/photos/domain/photo_share_link.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_common_widgets.dart';

/// 照片/相册分享对话框：密码 + 有效期 + 现有链接管理。
///
/// 返回（密码, 有效期选项）；取消返回 null。创建与撤销由调用方通过回调执行，
/// 创建结果由调用方提示。撤销成功后对话框关闭。
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
                      backgroundColor:
                          context.photosColors.surfaceContainerHigh,
                      title: Text(
                        title,
                        style: TextStyle(color: context.photosColors.onSurface),
                      ),
                      content: SizedBox(
                        width: 400,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 密码字段
                            TextField(
                              controller: passwordController,
                              style: TextStyle(
                                color: context.photosColors.onSurface,
                              ),
                              decoration: InputDecoration(
                                labelText:
                                    AppLocalizations.of(
                                      context,
                                    ).photosSharePassword,
                                hintText:
                                    AppLocalizations.of(
                                      context,
                                    ).photosSharePasswordHint,
                                hintStyle: TextStyle(
                                  color: context.photosColors.onSurfaceVariant
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                              obscureText: true,
                            ),
                            SizedBox(height: 12),
                            // 过期时间
                            Text(
                              AppLocalizations.of(context).photosShareExpiry,
                              style: TextStyle(
                                color: context.photosColors.onSurfaceVariant,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SegmentedButton<String>(
                              segments: [
                                ButtonSegment(
                                  value: '1d',
                                  label: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).photosShareExpiry1d,
                                  ),
                                ),
                                ButtonSegment(
                                  value: '7d',
                                  label: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).photosShareExpiry7d,
                                  ),
                                ),
                                ButtonSegment(
                                  value: '30d',
                                  label: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).photosShareExpiry30d,
                                  ),
                                ),
                                ButtonSegment(
                                  value: 'never',
                                  label: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).photosShareExpiryNever,
                                  ),
                                ),
                              ],
                              selected: {expiryOption},
                              onSelectionChanged:
                                  (v) => setDialogState(
                                    () => expiryOption = v.first,
                                  ),
                              style: ButtonStyle(
                                foregroundColor:
                                    WidgetStateProperty.resolveWith((states) {
                                      if (states.contains(
                                        WidgetState.selected,
                                      )) {
                                        return context
                                            .photosColors
                                            .primaryContainer;
                                      }
                                      return context
                                          .photosColors
                                          .onSurfaceVariant;
                                    }),
                              ),
                            ),
                            // 现有链接
                            if (shares.isNotEmpty) ...[
                              SizedBox(height: 16),
                              Text(
                                AppLocalizations.of(
                                  context,
                                ).photosExistingShareLinks,
                                style: TextStyle(
                                  color: context.photosColors.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 8),
                              ...shares.map(
                                (share) => ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    share.token,
                                    style: TextStyle(
                                      color: context.photosColors.onSurface,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).photosShareAccessCount(share.accessCount),
                                    style: TextStyle(
                                      color:
                                          context.photosColors.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    tooltip:
                                        AppLocalizations.of(context).coreDelete,
                                    icon: Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: context.photosColors.danger,
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
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(
                            AppLocalizations.of(context).photosCancel,
                          ),
                        ),
                        FilledButton(
                          onPressed:
                              () => Navigator.pop(ctx, (
                                passwordController.text.trim(),
                                expiryOption,
                              )),
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                context.photosColors.primaryContainer,
                            foregroundColor:
                                context.photosColors.onPrimaryContainer,
                          ),
                          child: Text(
                            AppLocalizations.of(context).photosCreateLink,
                          ),
                        ),
                      ],
                    ),
              ),
        ),
  );
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
