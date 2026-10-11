// 个人中心二级分区：安全与会话、通知偏好、服务器、关于。
//
// 与 profile_mobile_view.dart 同属 profile_page.dart 这一个 library，
// 因此直接复用其中的 _PmGroupLabel/_PmRow/_PmSwitch 等私有控件，
// 不需要把它们转正。
part of 'profile_page.dart';

/// 安全：修改密码行（对话框）+ 设备与会话列表。
class _PmSecuritySection extends ConsumerWidget {
  const _PmSecuritySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sessions = ref.watch(userSessionsProvider);
    final sessionList = sessions.asData?.value ?? const <UserSession>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _PmGroupLabel(l10n.profileCredentialsTitle),
        _PmRow(
          icon: Icons.password_rounded,
          label: l10n.profileRowChangePassword,
          subtitle: l10n.profileSectionSecuritySubtitle,
          onTap: () => unawaited(ChangePasswordDialog.show(context)),
        ),
        _PmTwoFactorRow(),
        _PmGroupLabel(l10n.profileRowSessions),
        if (sessions.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (sessionList.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                l10n.profileSessionsEmpty,
                style: TextStyle(
                  fontSize: 11, // ignore: font_size_whitelist
                  color: context.env.inkMuted,
                ),
              ),
            ),
          )
        else
          for (final session in sessionList)
            _PmSessionRow(
              session: session,
              onRevoke:
                  session.current
                      ? null
                      : () => unawaited(
                        ref
                            .read(profileCommandServiceProvider)
                            .revokeSession(session.id)
                            .whenComplete(
                              () => ref.invalidate(userSessionsProvider),
                            ),
                      ),
            ),
      ],
    );
  }
}

/// 两步验证行：状态副题 + 启用开关（开启走向导：密码→扫码→备份码；
/// 关闭走密码复核）；服务器强制必需时展示「必需」徽标不可关。
class _PmTwoFactorRow extends ConsumerWidget {
  const _PmTwoFactorRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(profileTwoFactorStatusProvider);
    return status.when(
      loading:
          () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      error:
          (_, _) => _PmRow(
            icon: Icons.verified_user_outlined,
            label: l10n.profileTwoFactorTitle,
            subtitle: l10n.profileTwoFactorLoadFailed,
            onTap: () => ref.invalidate(profileTwoFactorStatusProvider),
          ),
      data: (value) {
        final subtitle =
            value.enabled
                ? l10n.profileTwoFactorEnabled
                : (value.required
                    ? l10n.profileTwoFactorRequiredBadge
                    : l10n.profileTwoFactorDisabled);
        return _PmRow(
          icon: Icons.verified_user_outlined,
          label: l10n.profileTwoFactorTitle,
          subtitle: subtitle,
          trailing:
              value.required
                  ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: context.env.accentInk.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      l10n.profileTwoFactorRequiredBadge,
                      style: TextStyle(
                        fontSize: 8, // ignore: font_size_whitelist
                        fontWeight: FontWeight.w800,
                        color: context.env.accentInk,
                      ),
                    ),
                  )
                  : MobileEnvSwitch(
                    value: value.enabled,
                    onChanged: (_) async {
                      if (value.enabled) {
                        await ProfileTwoFactorCard.showDisableWizard(context);
                      } else {
                        await ProfileTwoFactorCard.showEnableWizard(context);
                      }
                      ref.invalidate(profileTwoFactorStatusProvider);
                    },
                  ),
        );
      },
    );
  }
}

/// 会话行：设备名/平台 + IP·最近活跃 + 当前徽标或下线钮。
class _PmSessionRow extends StatelessWidget {
  const _PmSessionRow({required this.session, required this.onRevoke});

  final UserSession session;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title =
        session.deviceName?.isNotEmpty == true
            ? session.deviceName!
            : session.clientPlatform;
    final subtitle = '${session.ipAddress} · ${session.lastActiveAt}';
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.env.line07)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.env.surfaceTint,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.devices_other_rounded,
                size: 17,
                color: context.env.inkMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12, // ignore: font_size_whitelist
                            fontWeight: FontWeight.w600,
                            color: context.env.ink,
                          ),
                        ),
                      ),
                      if (session.current) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: context.env.accentInk.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            l10n.profileSessionsCurrent,
                            style: TextStyle(
                              fontSize: 8, // ignore: font_size_whitelist
                              fontWeight: FontWeight.w800,
                              color: context.env.accentInk,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9, // ignore: font_size_whitelist
                      color: context.env.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (onRevoke != null)
              TextButton(
                onPressed: onRevoke,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE2A1A1),
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: Text(
                  l10n.profileSessionsRevoke,
                  style: const TextStyle(
                    fontSize: 10, // ignore: font_size_whitelist
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 通知偏好：总开关 + 声音/预览 + 类型开关（复用既有偏好控制器）。
class _PmNotificationsSection extends ConsumerWidget {
  const _PmNotificationsSection();

  Future<void> _save(WidgetRef ref, NotificationPreferences next) async {
    try {
      await ref.read(notificationPreferencesProvider.notifier).save(next);
    } on Exception {
      ref.invalidate(notificationPreferencesProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final preferences = ref.watch(notificationPreferencesProvider);
    final types = ref.watch(notificationTypesProvider);
    return preferences.when(
      loading:
          () => const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      error:
          (_, _) => Center(
            child: TextButton(
              onPressed: () => ref.invalidate(notificationPreferencesProvider),
              child: Text(l10n.coreRetry),
            ),
          ),
      data: (prefs) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _PmGroupLabel(l10n.profileNotificationSettings),
            _PmRow(
              icon: Icons.notifications_active_outlined,
              label: l10n.profileNotificationMasterSwitch,
              subtitle: l10n.profileNotificationMasterSwitchHint,
              trailing: _PmSwitch(
                value: prefs.enabled,
                onChanged:
                    (value) =>
                        unawaited(_save(ref, prefs.copyWith(enabled: value))),
              ),
            ),
            _PmRow(
              icon: Icons.music_note_outlined,
              label: l10n.profileNotificationSound,
              subtitle: l10n.profileNotificationSoundHint,
              trailing: _PmSwitch(
                value: prefs.sound,
                onChanged:
                    (value) =>
                        unawaited(_save(ref, prefs.copyWith(sound: value))),
              ),
            ),
            _PmRow(
              icon: Icons.visibility_outlined,
              label: l10n.profileNotificationPreview,
              subtitle: l10n.profileNotificationPreviewHint,
              trailing: _PmSwitch(
                value: prefs.showPreview,
                onChanged:
                    (value) => unawaited(
                      _save(ref, prefs.copyWith(showPreview: value)),
                    ),
              ),
            ),
            _PmGroupLabel(l10n.profileRowNotifications),
            types.when(
              loading:
                  () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              error:
                  (_, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      l10n.profileNotificationTypesLoadFailed,
                      style: TextStyle(
                        fontSize: 10, // ignore: font_size_whitelist
                        color: context.env.inkMuted,
                      ),
                    ),
                  ),
              data: (list) {
                final sorted = [...list]
                  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
                return Column(
                  children: [
                    for (final type in sorted)
                      _PmRow(
                        icon: Icons.campaign_outlined,
                        label: type.label,
                        subtitle: type.description ?? type.typeCode,
                        trailing: _PmSwitch(
                          value: prefs.types[type.typeCode] ?? true,
                          onChanged:
                              (value) => unawaited(
                                _save(
                                  ref,
                                  prefs.copyWith(
                                    types: {
                                      ...prefs.types,
                                      type.typeCode: value,
                                    },
                                  ),
                                ),
                              ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// 服务器：地址行 + 更换入口。
class _PmServerSection extends ConsumerWidget {
  const _PmServerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final environment = ref.watch(appEnvironmentProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _PmGroupLabel(l10n.profileServerAddress),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            environment?.apiBaseUrl ?? '-',
            style: TextStyle(
              fontSize: 13, // ignore: font_size_whitelist
              color: context.env.ink,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _PmPrimaryButton(
          label: l10n.profileSwitchServer,
          onPressed: () => unawaited(context.push('/server-setup?switch=1')),
        ),
      ],
    );
  }
}

/// 关于：版本信息。
class _PmAboutSection extends StatelessWidget {
  const _PmAboutSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _PmGroupLabel(l10n.profileGroupAbout),
        _PmRow(
          icon: Icons.auto_awesome_rounded,
          label: 'OmniNest',
          subtitle: 'v0.1.0 · self-hosted',
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            l10n.profileFooterTag,
            style: TextStyle(
              fontSize: 9, // ignore: font_size_whitelist
              color: context.env.inkFaint,
            ),
          ),
        ),
      ],
    );
  }
}
