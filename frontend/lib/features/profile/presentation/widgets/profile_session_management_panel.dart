import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';
import 'package:omninest/features/profile/application/profile_controller.dart';
import 'package:omninest/features/profile/domain/user_session.dart';

/// 展示并管理当前用户的活跃登录会话。
class ProfileSessionManagementPanel extends ConsumerStatefulWidget {
  const ProfileSessionManagementPanel({this.framed = true, super.key});

  final bool framed;

  @override
  ConsumerState<ProfileSessionManagementPanel> createState() =>
      _ProfileSessionManagementPanelState();
}

class _ProfileSessionManagementPanelState
    extends ConsumerState<ProfileSessionManagementPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      // 首次挂载时初始构建仍在飞行，跳过避免双请求；重进面板时失效缓存取新。
      final current = ref.read(userSessionsProvider);
      if (!current.isLoading) {
        ref.invalidate(userSessionsProvider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = _SessionContent(
      sessionsAsync: ref.watch(userSessionsProvider),
    );
    if (!widget.framed) {
      return Padding(padding: const EdgeInsets.all(20), child: content);
    }
    return WorkbenchPanel(padding: const EdgeInsets.all(24), child: content);
  }
}

class _SessionContent extends StatelessWidget {
  const _SessionContent({required this.sessionsAsync});

  final AsyncValue<List<UserSession>> sessionsAsync;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.globalColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.devices_rounded, size: 18, color: colors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.profileSessionManagement,
                style: TextStyle(
                  fontSize: AppTypography.titleMedium,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          l10n.profileSessionManagementSubtitle,
          style: TextStyle(
            fontSize: AppTypography.bodySmall,
            color: colors.onSurfaceVariant.withValues(alpha: 0.78),
          ),
        ),
        const SizedBox(height: 16),
        sessionsAsync.when(
          loading:
              () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
          error:
              (_, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.profileSessionsLoadFailed),
              ),
          data: (sessions) {
            if (sessions.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    l10n.profileNoSessions,
                    style: TextStyle(
                      fontSize: AppTypography.bodyMedium,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final session in sessions) _SessionTile(session: session),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.session});

  final UserSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.globalColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _platformIcon(session.clientPlatform),
              size: 20,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.effectiveDeviceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTypography.bodyLarge,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${session.ipAddress} · ${_formatTime(session.lastActiveAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTypography.bodySmall,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _confirmRevoke(context, ref),
            icon: Icon(Icons.logout_rounded, size: 18, color: colors.error),
            tooltip: l10n.profileRevokeSession,
          ),
        ],
      ),
    );
  }

  IconData _platformIcon(String platform) {
    return switch (platform.toLowerCase()) {
      'web' => Icons.language_rounded,
      'android' => Icons.phone_android_rounded,
      'ios' => Icons.phone_iphone_rounded,
      'desktop' || 'windows' || 'macos' || 'linux' => Icons.computer_rounded,
      _ => Icons.devices_rounded,
    };
  }

  String _formatTime(String isoTime) {
    final dateTime = DateTime.tryParse(isoTime)?.toLocal();
    if (dateTime == null) return isoTime;
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${dateTime.year}-${twoDigits(dateTime.month)}-'
        '${twoDigits(dateTime.day)} ${twoDigits(dateTime.hour)}:'
        '${twoDigits(dateTime.minute)}';
  }

  Future<void> _confirmRevoke(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.profileRevokeSessionConfirm),
            content: Text(l10n.profileRevokeSessionMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.coreCancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.profileRevokeSession),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(profileCommandServiceProvider).revokeSession(session.id);
      if (!context.mounted) return;
      ref.invalidate(userSessionsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.profileSessionRevoked)));
      }
    } on Exception {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.profileSessionRevokeFailed)),
        );
      }
    }
  }
}
