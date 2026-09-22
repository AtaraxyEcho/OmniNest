import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/presentation/widgets/music_platform_login_controls.dart';

/// 已登录用户信息与断开操作。
class MusicPlatformLoggedInCard extends ConsumerStatefulWidget {
  const MusicPlatformLoggedInCard({
    required this.user,
    required this.accentColor,
    super.key,
  });

  final PlatformUserInfo user;
  final Color accentColor;

  @override
  ConsumerState<MusicPlatformLoggedInCard> createState() =>
      _MusicPlatformLoggedInCardState();
}

class _MusicPlatformLoggedInCardState
    extends ConsumerState<MusicPlatformLoggedInCard> {
  bool _loggingOut = false;

  /// 断开平台：二次确认 → 调接口 → 清理本地派生状态 → 反馈结果。
  ///
  /// 失败必须显式反馈：此前该流程的 Future 无接收方，服务端异常时界面既不清理
  /// 也不提示，用户观感是"点了没反应"。
  Future<void> _logout() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showMusicPlatformConfirmDialog(
      context: context,
      title: l10n.musicPlatformLogoutConfirmTitle,
      message: l10n.musicPlatformLogoutConfirmMessage,
      confirmLabel: l10n.musicPlatformLogout,
      cancelLabel: l10n.adminCancel,
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _loggingOut = true);
    try {
      final removedItems = await ref
          .read(musicCenterControllerProvider.notifier)
          .platformLogout('netease');
      if (!mounted) {
        return;
      }
      _showMessage(
        removedItems > 0
            ? '${l10n.musicPlatformLogoutSuccess}，'
                '${l10n.musicPlatformLogoutQueuePurged(removedItems)}'
            : l10n.musicPlatformLogoutSuccess,
      );
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(
        l10n.musicSaveFailed(describeUserFacingError(error).message),
      );
    } finally {
      if (mounted) {
        setState(() => _loggingOut = false);
      }
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final l10n = AppLocalizations.of(context);
    final user = widget.user;
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: widget.accentColor.withValues(alpha: 0.15),
          backgroundImage:
              user.avatarUrl.isNotEmpty ? NetworkImage(user.avatarUrl) : null,
          child:
              user.avatarUrl.isEmpty
                  ? Icon(
                    Icons.person_rounded,
                    color: widget.accentColor,
                    size: 22,
                  )
                  : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      user.nickname.isEmpty
                          ? l10n.musicPlatformAnonymousUser
                          : user.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: AppTypography.titleMedium,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (user.vip) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: widget.accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        l10n.musicPlatformVipBadge,
                        style: TextStyle(
                          color: widget.accentColor,
                          fontSize: AppTypography.labelSmall,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                l10n.musicPlatformUserId(user.userId),
                style: TextStyle(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: AppTypography.bodySmall,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: colors.danger,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onPressed: _loggingOut ? null : () => unawaited(_logout()),
          child:
              _loggingOut
                  ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.danger,
                    ),
                  )
                  : Text(
                    l10n.musicPlatformLogout,
                    style: const TextStyle(
                      fontSize: AppTypography.bodyMedium,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
        ),
      ],
    );
  }
}
