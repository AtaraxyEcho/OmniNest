part of 'desktop_settings_page.dart';

/// 通知偏好：与服务端偏好同一份快照，改动立即回写（失败回滚）。
class _NotificationsSection extends ConsumerWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final prefs = ref.watch(notificationPreferencesProvider).asData?.value;
    if (prefs == null) {
      return _Card(
        title: l10n.settingsNotification,
        child: Text(
          ref.watch(notificationPreferencesProvider).hasError
              ? l10n.notificationLoadFailed
              : '',
          style: DesktopType.dense(skin.text3),
        ),
      );
    }
    final controller = ref.read(notificationPreferencesProvider.notifier);
    Future<void> save(NotificationPreferences next) async {
      try {
        await controller.save(next);
      } on Object catch (error) {
        if (context.mounted) {
          showDesktopToast(
            context,
            failureToast(l10n, l10n.settingsNotification, error),
            kind: DesktopToastKind.error,
            icon: DesktopIcons.info,
          );
        }
      }
    }

    return _Card(
      title: l10n.settingsNotification,
      subtitle: l10n.desktopNotificationSettings,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingToggleRow(
            label: l10n.settingsNotificationEnable,
            hint: l10n.settingsNotificationEnableHint,
            value: prefs.enabled,
            onChanged: (value) => save(prefs.copyWith(enabled: value)),
          ),
          _SettingToggleRow(
            label: l10n.profileNotificationSound,
            hint: l10n.profileNotificationSoundHint,
            value: prefs.sound,
            onChanged: (value) => save(prefs.copyWith(sound: value)),
          ),
          _SettingToggleRow(
            label: l10n.profileNotificationPreview,
            hint: l10n.profileNotificationPreviewHint,
            value: prefs.showPreview,
            onChanged: (value) => save(prefs.copyWith(showPreview: value)),
          ),
          _SettingToggleRow(
            label: l10n.desktopSettingsForegroundBanner,
            hint: l10n.notificationForegroundToastToggleSubtitle,
            value: prefs.foregroundBanner,
            onChanged: (value) => save(prefs.copyWith(foregroundBanner: value)),
          ),
          _SettingToggleRow(
            label: l10n.profileNotificationEmail,
            hint: l10n.profileNotificationEmailHint,
            value: prefs.emailNotification,
            onChanged:
                (value) => save(prefs.copyWith(emailNotification: value)),
          ),
          _SettingToggleRow(
            label: l10n.notificationQuietHours,
            hint: l10n.notificationQuietHoursHint,
            value: prefs.quietHours.enabled,
            onChanged:
                (value) => save(
                  prefs.copyWith(
                    quietHours: prefs.quietHours.copyWith(enabled: value),
                  ),
                ),
          ),
          if (prefs.quietHours.enabled)
            Padding(
              padding: const EdgeInsets.only(left: 0, top: 4, bottom: 8),
              child: Text(
                '${l10n.notificationQuietHoursStart} '
                '${prefs.quietHours.start} · '
                '${l10n.notificationQuietHoursEnd} '
                '${prefs.quietHours.end}',
                style: DesktopType.caption(skin.text3),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingToggleRow extends StatelessWidget {
  const _SettingToggleRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: skin.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: DesktopType.bodyStrong(skin.text)),
                const SizedBox(height: 2),
                Text(hint, style: DesktopType.caption(skin.text3)),
              ],
            ),
          ),
          DesktopToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// 关于与更新：展示版本、服务器地址，并可主动检查新版本。
class _AboutSection extends ConsumerStatefulWidget {
  const _AboutSection();

  @override
  ConsumerState<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends ConsumerState<_AboutSection> {
  bool _checking = false;
  AppVersionInfo? _info;
  String? _error;

  Future<void> _check() async {
    if (_checking) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() {
      _checking = true;
      _error = null;
      _info = null;
    });
    try {
      final info =
          await ref.read(appVersionControllerProvider).checkForUpdate();
      if (mounted) {
        setState(() => _info = info);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = errorReason(error, l10n));
      }
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final host =
        Uri.tryParse(ref.read(appEnvironmentProvider)?.apiBaseUrl ?? '')?.host;
    final latest = _info?.latestVersion;
    return _Card(
      title: l10n.settingsAbout,
      subtitle: l10n.settingsAboutHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KvRow(
            label: l10n.desktopSettingsServerVersion,
            value: (host == null || host.isEmpty) ? '—' : host,
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Text(_error!, style: DesktopType.caption(DesktopPalette.bad))
          else if (latest != null)
            Text(
              l10n.settingsNewVersionFound(latest),
              style: DesktopType.bodyStrong(skin.accent),
            )
          else if (_info != null)
            Text(
              l10n.desktopSettingsUpToDate,
              style: DesktopType.bodyStrong(skin.text2),
            ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: DesktopButton(
              label: l10n.settingsCheckUpdate,
              icon: DesktopIcons.retry,
              variant: DesktopButtonVariant.soft,
              busy: _checking,
              onPressed: _checking ? null : _check,
            ),
          ),
        ],
      ),
    );
  }
}

/// 安全与设备：改密 + 活跃会话，两件事都直接打真实接口。
class _SecuritySection extends ConsumerStatefulWidget {
  const _SecuritySection();

  @override
  ConsumerState<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends ConsumerState<_SecuritySection> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final current = _current.text;
    final next = _next.text;
    if (current.isEmpty || next.isEmpty) {
      setState(() => _error = l10n.changePasswordEnterNew);
      return;
    }
    if (next.length < 8) {
      setState(() => _error = l10n.changePasswordMinLength);
      return;
    }
    if (next != _confirm.text) {
      setState(() => _error = l10n.changePasswordMismatch);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(profileCommandServiceProvider)
          .changePassword(oldPassword: current, newPassword: next);
      if (!mounted) {
        return;
      }
      _current.clear();
      _next.clear();
      _confirm.clear();
      showDesktopToast(
        context,
        l10n.changePasswordSuccess,
        icon: DesktopIcons.check,
      );
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = failureToast(l10n, l10n.changePasswordFailed, error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _revoke(UserSession session) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDesktopDialog<bool>(
      context,
      builder:
          (dialogContext) => DesktopDialog(
            width: 440,
            eyebrow: l10n.desktopSecuritySessions,
            title: l10n.profileRevokeSessionConfirm,
            content: Text(
              l10n.profileRevokeSessionMessage,
              style: DesktopType.dense(DesktopSkin.of(context).text2),
            ),
            actions: [
              DesktopButton(
                label: l10n.filesCancel,
                onPressed: () => closeDesktopModal(dialogContext, false),
              ),
              DesktopButton(
                label: l10n.profileSessionsRevoke,
                icon: DesktopIcons.signOut,
                variant: DesktopButtonVariant.danger,
                onPressed: () => closeDesktopModal(dialogContext, true),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref.read(profileCommandServiceProvider).revokeSession(session.id);
      ref.invalidate(userSessionsProvider);
      if (mounted) {
        showDesktopToast(context, l10n.profileSessionRevoked);
      }
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.profileSessionRevokeFailed, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final sessions = ref.watch(userSessionsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          title: l10n.changePasswordConfirm,
          subtitle: l10n.changePasswordMinLength,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DesktopTextField(
                keyName: 'settings-current-password',
                controller: _current,
                hint: l10n.changePasswordOldPassword,
                obscure: true,
                height: 38,
              ),
              const SizedBox(height: 10),
              DesktopTextField(
                keyName: 'settings-new-password',
                controller: _next,
                hint: l10n.changePasswordNewPassword,
                obscure: true,
                height: 38,
              ),
              const SizedBox(height: 10),
              DesktopTextField(
                keyName: 'settings-confirm-password',
                controller: _confirm,
                hint: l10n.changePasswordConfirmNew,
                obscure: true,
                height: 38,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: DesktopType.caption(DesktopPalette.bad)),
              ],
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: DesktopButton(
                  label: l10n.changePasswordConfirm,
                  icon: DesktopIcons.lock,
                  variant: DesktopButtonVariant.primary,
                  busy: _saving,
                  onPressed: _saving ? null : _submit,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Card(
          title: l10n.profileActiveSessions,
          subtitle: l10n.profileSessionManagementSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sessions.isLoading && !sessions.hasValue)
                Text(
                  l10n.profileSessionManagementSubtitle,
                  style: DesktopType.caption(skin.text3),
                )
              else if (sessions.hasError)
                Text(
                  l10n.profileSessionsLoadFailed,
                  style: DesktopType.caption(DesktopPalette.bad),
                )
              else if ((sessions.asData?.value ?? const <UserSession>[])
                  .isEmpty)
                Text(
                  l10n.profileNoSessions,
                  style: DesktopType.caption(skin.text3),
                )
              else
                for (final session in sessions.asData!.value)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: skin.line)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          session.current
                              ? DesktopIcons.device
                              : DesktopIcons.cloud,
                          size: 15,
                          color: session.current ? skin.accent : skin.text3,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      session.deviceName?.isNotEmpty == true
                                          ? session.deviceName!
                                          : session.clientPlatform,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: DesktopType.bodyStrong(skin.text),
                                    ),
                                  ),
                                  if (session.current) ...[
                                    const SizedBox(width: 8),
                                    DesktopChip(l10n.profileSessionsCurrent),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${session.ipAddress} · ${session.lastActiveAt}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DesktopType.caption(skin.text3),
                              ),
                            ],
                          ),
                        ),
                        if (!session.current)
                          DesktopButton(
                            label: l10n.profileSessionsRevoke,
                            icon: DesktopIcons.signOut,
                            variant: DesktopButtonVariant.ghost,
                            onPressed: () => _revoke(session),
                          ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 连接服务：外部存储账号的监管视图（创建/浏览仍在文件页）。
class _ServicesSection extends ConsumerWidget {
  const _ServicesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final state = ref.watch(fileBrowserControllerProvider).asData?.value;
    final accounts =
        state?.externalAccounts ?? const <ExternalStorageAccount>[];
    final controller = ref.read(fileBrowserControllerProvider.notifier);
    return _Card(
      title: l10n.desktopConnectedServices,
      subtitle: l10n.filesExternalStorageDesc,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.filesExternalEmptyMessage,
                    style: DesktopType.dense(skin.text3),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    children: [
                      DesktopButton(
                        label: l10n.filesExternalStorage,
                        icon: DesktopIcons.server,
                        variant: DesktopButtonVariant.primary,
                        onPressed:
                            () => desktopPush(
                              context,
                              '/files?section=externalStorage',
                            ),
                      ),
                      DesktopButton(
                        label: l10n.desktopServicesRefresh,
                        icon: DesktopIcons.retry,
                        variant: DesktopButtonVariant.ghost,
                        onPressed:
                            () => unawaited(
                              controller.loadSection(
                                FileManagerSection.externalStorage,
                              ),
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            for (final account in accounts)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: skin.line)),
                ),
                child: Row(
                  children: [
                    Icon(DesktopIcons.cloud, size: 16, color: skin.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            account.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.bodyStrong(skin.text),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            account.provider,
                            style: DesktopType.caption(skin.text3),
                          ),
                        ],
                      ),
                    ),
                    DesktopChip(account.status),
                    const SizedBox(width: 8),
                    DesktopButton(
                      label: l10n.filesTestConnection,
                      icon: DesktopIcons.check,
                      variant: DesktopButtonVariant.ghost,
                      onPressed:
                          () => unawaited(
                            controller.testExternalStorageConnection(
                              account.id,
                            ),
                          ),
                    ),
                    const SizedBox(width: 6),
                    DesktopButton(
                      label: l10n.desktopFilesDisable,
                      icon: DesktopIcons.close,
                      variant: DesktopButtonVariant.ghost,
                      onPressed:
                          () => unawaited(
                            controller.disableExternalStorage(account),
                          ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
