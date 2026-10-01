import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_edit_dialog.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_section_card.dart';

/// 账户基本信息卡：方形头像 + 只读资料网格 + mono 元信息行。
///
/// 编辑资料经 [ProfileEditDialog] 窗口承载（canEditProfile =
/// profile:write 时展示入口），卡内字段一律只读展示。
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
    required this.canEditProfile,
    required this.onSaveProfile,
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
  final bool canEditProfile;

  /// 保存资料；返回是否成功（窗口内据此决定关闭或内联报错）。
  final Future<bool> Function(String displayName, String email) onSaveProfile;

  void _openEditDialog(BuildContext context) {
    ProfileEditDialog.show(
      context,
      initialDisplayName: displayName,
      initialEmail: email,
      onSave: onSaveProfile,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ProfileSectionCard(
      title: l10n.profileGeneralInfoTitle,
      trailing:
          canEditProfile
              ? WorkstationActionButton(
                label: l10n.profileEditProfile,
                icon: Icons.edit_outlined,
                onPressed: () => _openEditDialog(context),
              )
              : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AvatarBlock(
            displayName: displayName,
            avatarUrl: avatarUrl,
            onEditAvatar: onEditAvatar,
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 620;
              final columnWidth =
                  twoColumns
                      ? (constraints.maxWidth - 16) / 2
                      : double.infinity;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: columnWidth,
                    child: _ProfileField(
                      label: l10n.profileDisplayNameLabel,
                      value: displayName,
                    ),
                  ),
                  SizedBox(
                    width: columnWidth,
                    child: _ProfileField(
                      label: l10n.profileUsername,
                      value: username.isEmpty ? '-' : '@$username',
                      trailingIcon: Icons.lock_outline_rounded,
                      mono: true,
                    ),
                  ),
                  SizedBox(
                    width: twoColumns ? constraints.maxWidth : double.infinity,
                    child: _ProfileField(
                      label: l10n.profileEmail,
                      value: email,
                      mono: true,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          _AccountMetaRow(userId: userId, role: role, unreadCount: unreadCount),
        ],
      ),
    );
  }
}

class _AvatarBlock extends StatelessWidget {
  const _AvatarBlock({
    required this.displayName,
    required this.avatarUrl,
    required this.onEditAvatar,
  });

  final String displayName;
  final String? avatarUrl;
  final VoidCallback onEditAvatar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final initial = displayName.isEmpty ? '?' : displayName.characters.first;
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child:
              avatarUrl?.isNotEmpty == true
                  ? Image.network(
                    avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _initial(initial, scheme),
                  )
                  : _initial(initial, scheme),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WorkstationActionButton(
              label: l10n.profileEditAvatar,
              icon: Icons.upload_outlined,
              onPressed: onEditAvatar,
            ),
            const SizedBox(height: 6),
            Text(
              l10n.profileAvatarHint,
              style: TextStyle(
                fontSize: AppTypography.labelSmall,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _initial(String initial, ColorScheme scheme) {
    return Center(
      child: Text(
        initial.toUpperCase(),
        style: TextStyle(
          fontFamily: AppTypography.monoFamily,
          fontFamilyFallback: AppTypography.monoFamilyFallback,
          fontSize: AppTypography.headlineSmall,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}

/// 只读资料字段：mono 小标签 + 细线值框（可选锁图标，值可选中复制）。
class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.label,
    required this.value,
    this.trailingIcon,
    this.mono = false,
  });

  final String label;
  final String value;
  final IconData? trailingIcon;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTypography.monoFamily,
            fontFamilyFallback: AppTypography.monoFamilyFallback,
            fontSize: AppTypography.labelSmall,
            fontWeight: FontWeight.w500,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: AppTypography.bodyMedium,
                    color: scheme.onSurface,
                    fontFamily: mono ? AppTypography.monoFamily : null,
                    fontFamilyFallback:
                        mono ? AppTypography.monoFamilyFallback : null,
                  ),
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 8),
                Icon(
                  trailingIcon,
                  size: 13,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// mono 元信息行：用户 ID / 角色 / 账户状态 / 未读通知。
class _AccountMetaRow extends StatelessWidget {
  const _AccountMetaRow({
    required this.userId,
    required this.role,
    required this.unreadCount,
  });

  final String userId;
  final String role;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final items = <({String label, String value})>[
      if (userId.isNotEmpty) (label: l10n.profileUserId, value: userId),
      (label: l10n.profileRoleLabel, value: '[${role.toUpperCase()}]'),
      (label: l10n.profileAccountStatus, value: l10n.profileStatusNormal),
      (label: l10n.profileUnreadNotifications, value: '$unreadCount'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 8,
        children: [
          for (final item in items)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.label.toUpperCase(),
                  style: TextStyle(
                    fontFamily: AppTypography.monoFamily,
                    fontFamilyFallback: AppTypography.monoFamilyFallback,
                    fontSize: AppTypography.labelMicro,
                    letterSpacing: 1.2,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  item.value,
                  style: TextStyle(
                    fontFamily: AppTypography.monoFamily,
                    fontFamilyFallback: AppTypography.monoFamilyFallback,
                    fontSize: AppTypography.labelSmall,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
