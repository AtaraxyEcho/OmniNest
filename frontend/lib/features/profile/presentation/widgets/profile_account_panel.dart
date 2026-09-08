import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/core/widgets/workbench_panel.dart';

class ProfileAccountPanel extends StatelessWidget {
  const ProfileAccountPanel({
    required this.displayName,
    required this.username,
    required this.email,
    required this.userId,
    required this.role,
    required this.avatarUrl,
    required this.unreadCount,
    required this.onEditAvatar,
    super.key,
  });

  final String displayName;
  final String username;
  final String email;
  final String userId;
  final String role;
  final String? avatarUrl;
  final int unreadCount;
  final VoidCallback onEditAvatar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.globalColors;
    return WorkbenchPanel(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final details = <({String label, String value})>[
            (label: l10n.profileUsername, value: username),
            (label: l10n.profileEmail, value: email),
            if (userId.isNotEmpty) (label: l10n.profileUserId, value: userId),
            (
              label: l10n.profileUnreadNotifications,
              value: unreadCount.toString(),
            ),
            (label: l10n.profileAccountStatus, value: l10n.profileStatusNormal),
          ];
          final detailWidth =
              constraints.maxWidth >= 620
                  ? (constraints.maxWidth - 24) / 2
                  : constraints.maxWidth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AccountHeader(
                displayName: displayName,
                username: username,
                role: _roleLabel(l10n),
                avatarUrl: avatarUrl,
                onEditAvatar: onEditAvatar,
              ),
              const SizedBox(height: 24),
              Divider(color: colors.outlineVariant),
              const SizedBox(height: 4),
              Wrap(
                spacing: 24,
                children: [
                  for (final detail in details)
                    SizedBox(
                      width: detailWidth,
                      child: _DetailItem(
                        label: detail.label,
                        value: detail.value,
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  String _roleLabel(AppLocalizations l10n) {
    return switch (role) {
      'SUPER_ADMIN' => l10n.profileRoleSuperAdmin,
      'ADMIN' => l10n.profileRoleAdmin,
      _ => l10n.profileRoleMember,
    };
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.displayName,
    required this.username,
    required this.role,
    required this.avatarUrl,
    required this.onEditAvatar,
  });

  final String displayName;
  final String username;
  final String role;
  final String? avatarUrl;
  final VoidCallback onEditAvatar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.globalColors;
    return Wrap(
      spacing: 18,
      runSpacing: 14,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _AccountAvatar(displayName: displayName, avatarUrl: avatarUrl),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 180, maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '@$username',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      role,
                      style: TextStyle(
                        color: colors.onPrimaryContainer,
                        fontSize: AppTypography.labelSmall,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: onEditAvatar,
          icon: const Icon(Icons.photo_camera_outlined, size: 18),
          label: Text(l10n.profileEditAvatar),
        ),
      ],
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.displayName, required this.avatarUrl});

  final String displayName;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final colors = context.globalColors;
    final initial = displayName.isEmpty ? '?' : displayName.characters.first;
    return Container(
      width: 72,
      height: 72,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.primaryContainer,
      ),
      child:
          avatarUrl?.isNotEmpty == true
              ? Image.network(
                avatarUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback(initial, colors),
              )
              : _fallback(initial, colors),
    );
  }

  Widget _fallback(String initial, GlobalThemeColors colors) {
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          color: colors.onPrimaryContainer,
          fontSize: AppTypography.headlineMedium,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  const _DetailItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.globalColors;
    return Container(
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: AppTypography.bodySmall,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          SelectableText(
            value,
            maxLines: 2,
            style: TextStyle(color: colors.onSurface, height: 1.35),
          ),
        ],
      ),
    );
  }
}
