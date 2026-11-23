part of 'desktop_settings_page.dart';

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
    if (next.length > 64 || utf8.encode(next).length > 72) {
      setState(() => _error = l10n.changePasswordMaxLength);
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
    final platform = session.clientPlatform.trim();
    final detail =
        platform.isEmpty
            ? session.effectiveDeviceName
            : '${session.effectiveDeviceName} · $platform';
    final confirmed = await showDesktopDialog<bool>(
      context,
      builder:
          (dialogContext) => DesktopDialog(
            width: 440,
            eyebrow: l10n.profileActiveSessions,
            title: l10n.desktopSignOut,
            lead: Icon(
              DesktopIcons.signOut,
              size: 20,
              color: DesktopPalette.bad,
            ),
            content: Text(
              detail,
              style: DesktopType.dense(DesktopSkin.of(context).text2),
            ),
            actions: [
              DesktopButton(
                label: l10n.filesCancel,
                onPressed: () => closeDesktopModal(dialogContext, false),
              ),
              DesktopButton(
                label: l10n.desktopSignOut,
                icon: DesktopIcons.signOut,
                variant: DesktopButtonVariant.danger,
                onPressed: () => closeDesktopModal(dialogContext, true),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(profileCommandServiceProvider).revokeSession(session.id);
      if (!mounted) return;
      ref.invalidate(userSessionsProvider);
      showDesktopToast(
        context,
        l10n.desktopSessionSignedOut(session.effectiveDeviceName),
        icon: DesktopIcons.signOut,
      );
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
    final orderedSessions = [...?sessions.asData?.value]..sort(
      (left, right) => (right.current ? 1 : 0).compareTo(left.current ? 1 : 0),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          title: l10n.profileChangePassword,
          subtitle: l10n.profileChangePasswordSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DesktopTextField(
                keyName: 'settings-current-password',
                controller: _current,
                label: l10n.changePasswordOldPassword,
                obscure: true,
                required: true,
                height: 40,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              DesktopTextField(
                keyName: 'settings-new-password',
                controller: _next,
                label: l10n.changePasswordNewPassword,
                obscure: true,
                required: true,
                height: 40,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
              _PasswordStrengthMeter(score: _passwordStrength),
              const SizedBox(height: 14),
              DesktopTextField(
                keyName: 'settings-confirm-password',
                controller: _confirm,
                label: l10n.changePasswordConfirmNew,
                obscure: true,
                required: true,
                height: 40,
                onChanged: (_) => setState(() {}),
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
                  onPressed: _canSubmitPasswordChange ? _submit : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Card(
          title: l10n.profileTwoFactorTitle,
          child: const ProfileTwoFactorCard(framed: false, showTitle: false),
        ),
        const SizedBox(height: 18),
        _Card(
          title: l10n.profileActiveSessions,
          subtitle: l10n.profileSessionManagementSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sessions.isLoading && !sessions.hasValue)
                const DesktopSkeletonRows(count: 3)
              else if (sessions.hasError && !sessions.hasValue)
                DesktopErrorView(
                  message: l10n.profileSessionsLoadFailed,
                  onRetry: () => ref.invalidate(userSessionsProvider),
                  retryLabel: l10n.commonRetry,
                  minHeightFactor: 0.16,
                )
              else if ((sessions.asData?.value ?? const <UserSession>[])
                  .isEmpty)
                Text(
                  l10n.profileNoSessions,
                  style: DesktopType.caption(skin.text3),
                )
              else
                for (var index = 0; index < orderedSessions.length; index++)
                  _SettingsSessionRow(
                    session: orderedSessions[index],
                    first: index == 0,
                    onSignOut: () => _revoke(orderedSessions[index]),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  int get _passwordStrength {
    final password = _next.text;
    return [
      password.length > 7,
      RegExp(r'[A-Z]').hasMatch(password),
      RegExp(r'[0-9]').hasMatch(password),
      RegExp(r'[^A-Za-z0-9]').hasMatch(password),
    ].where((matched) => matched).length;
  }

  bool get _canSubmitPasswordChange =>
      !_saving &&
      _current.text.isNotEmpty &&
      _passwordStrength >= 2 &&
      _next.text.length <= 64 &&
      utf8.encode(_next.text).length <= 72 &&
      _next.text == _confirm.text;
}

class _SettingsSessionRow extends StatelessWidget {
  const _SettingsSessionRow({
    required this.session,
    required this.first,
    required this.onSignOut,
  });

  final UserSession session;
  final bool first;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final activity =
        session.current
            ? l10n.profileSessionCurrent
            : _sessionActivityText(l10n, session.lastActiveAt);
    final platform = session.clientPlatform.trim();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: skin.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        session.effectiveDeviceName,
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
                  [if (platform.isNotEmpty) platform, activity].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.caption(skin.text3),
                ),
              ],
            ),
          ),
          if (!session.current) ...[
            const SizedBox(width: 20),
            DesktopButton(
              label: l10n.desktopSignOut,
              variant: DesktopButtonVariant.ghost,
              onPressed: onSignOut,
            ),
          ],
        ],
      ),
    );
  }
}

String _sessionActivityText(AppLocalizations l10n, String lastActiveAt) {
  final activeAt = DateTime.tryParse(lastActiveAt)?.toLocal();
  if (activeAt == null) return lastActiveAt;
  final difference = DateTime.now().difference(activeAt);
  if (difference.inMinutes < 1) return l10n.tasksTimeMinutesAgo(0);
  if (difference.inMinutes < 60) {
    return l10n.tasksTimeMinutesAgo(difference.inMinutes);
  }
  if (difference.inHours < 24) {
    return l10n.tasksTimeHoursAgo(difference.inHours);
  }
  if (difference.inDays == 1) return l10n.musicHistoryYesterday;
  if (difference.inDays < 7) return l10n.tasksTimeDaysAgo(difference.inDays);
  final month = activeAt.month.toString().padLeft(2, '0');
  final day = activeAt.day.toString().padLeft(2, '0');
  return activeAt.year == DateTime.now().year
      ? '$month-$day'
      : '${activeAt.year}-$month-$day';
}

class _PasswordStrengthMeter extends StatelessWidget {
  const _PasswordStrengthMeter({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final tone = switch (score) {
      0 => skin.line,
      1 => DesktopPalette.bad,
      2 => DesktopPalette.warn,
      _ => skin.accent,
    };
    final label = switch (score) {
      0 => l10n.changePasswordStrengthTooShort,
      1 => l10n.setupPasswordStrengthWeak,
      2 => l10n.setupPasswordStrengthFair,
      3 => l10n.setupPasswordStrengthGood,
      _ => l10n.setupPasswordStrengthStrong,
    };
    return Row(
      children: [
        for (var index = 0; index < 4; index++) ...[
          if (index > 0) const SizedBox(width: 5),
          Expanded(
            child: AnimatedContainer(
              duration: DesktopMotion.fast,
              curve: DesktopMotion.ease,
              height: 4,
              decoration: BoxDecoration(
                color: index < score ? tone : skin.line,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
        const SizedBox(width: 8),
        SizedBox(
          width: 56,
          child: Text(label, style: DesktopType.caption(skin.text3)),
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
    final music = ref.watch(musicCenterControllerProvider).asData?.value;
    final scan = ref.watch(musicScanJobControllerProvider);
    final platformUser = music?.neteaseUserInfo;
    final localTracks = music?.dashboard.trackCount ?? 0;
    final scanDetail =
        scan.job == null
            ? l10n.musicScanIdleHint
            : l10n.musicScanStatus(
              scan.job!.id,
              scan.job!.status,
              scan.job!.progress,
              scan.job!.scannedFiles,
            );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          title: l10n.musicPlatformLoginTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ServiceRow(
                title: l10n.musicPlatformNeteaseName,
                detail:
                    platformUser == null
                        ? l10n.musicPlatformNeteaseQrHint
                        : '${platformUser.nickname.isEmpty ? l10n.musicPlatformAnonymousUser : platformUser.nickname} · ${l10n.musicPlatformUserId(platformUser.userId)}',
                trailing:
                    platformUser == null
                        ? DesktopButton(
                          label: l10n.musicPlatformQrAction,
                          icon: DesktopIcons.link,
                          variant: DesktopButtonVariant.primary,
                          onPressed: () => PlatformLoginSheet.show(context),
                        )
                        : DesktopButton(
                          label: l10n.musicPlatformLogout,
                          icon: DesktopIcons.signOut,
                          variant: DesktopButtonVariant.ghost,
                          onPressed: () => _disconnectMusic(context, ref),
                        ),
              ),
              const SizedBox(height: 4),
              _ServiceRow(
                title: l10n.filesLocalLibrary,
                detail: '$localTracks · $scanDetail',
                trailing: DesktopButton(
                  label:
                      scan.polling
                          ? l10n.musicScanStatusLabel
                          : l10n.musicStartScan,
                  icon: scan.polling ? DesktopIcons.clock : DesktopIcons.retry,
                  variant: DesktopButtonVariant.soft,
                  onPressed:
                      scan.polling ? null : () => _startMusicScan(context, ref),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Card(
          title: l10n.desktopServicesOther,
          child: _ServiceRow(
            title: l10n.desktopLastFmScrobbling,
            detail: l10n.desktopLastFmUnavailable,
            trailing: DesktopChip(l10n.adminNotConfigured),
          ),
        ),
      ],
    );
  }
}

Future<void> _disconnectMusic(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDesktopDialog<bool>(
    context,
    builder:
        (dialogContext) => DesktopDialog(
          width: 440,
          eyebrow: l10n.musicPlatformLoginTitle,
          title: l10n.musicPlatformLogoutConfirmTitle,
          content: Text(l10n.musicPlatformLogoutConfirmMessage),
          actions: [
            DesktopButton(
              label: l10n.filesCancel,
              onPressed: () => closeDesktopModal(dialogContext, false),
            ),
            DesktopButton(
              label: l10n.musicPlatformLogout,
              icon: DesktopIcons.signOut,
              variant: DesktopButtonVariant.danger,
              onPressed: () => closeDesktopModal(dialogContext, true),
            ),
          ],
        ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await ref
        .read(musicCenterControllerProvider.notifier)
        .platformLogout('netease');
    if (context.mounted) {
      showDesktopToast(
        context,
        l10n.musicPlatformLogoutSuccess,
        icon: DesktopIcons.check,
      );
    }
  } on Object catch (error) {
    if (context.mounted) {
      showDesktopToast(
        context,
        failureToast(l10n, l10n.musicPlatformLogout, error),
        kind: DesktopToastKind.error,
        icon: DesktopIcons.info,
      );
    }
  }
}

Future<void> _startMusicScan(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDesktopDialog<bool>(
    context,
    builder:
        (dialogContext) => DesktopDialog(
          width: 440,
          eyebrow: l10n.musicPlatformLoginTitle,
          title: l10n.musicStartScan,
          content: Text(l10n.musicScanStartConfirmMessage),
          actions: [
            DesktopButton(
              label: l10n.filesCancel,
              onPressed: () => closeDesktopModal(dialogContext, false),
            ),
            DesktopButton(
              label: l10n.musicStartScan,
              icon: DesktopIcons.retry,
              variant: DesktopButtonVariant.primary,
              onPressed: () => closeDesktopModal(dialogContext, true),
            ),
          ],
        ),
  );
  if (confirmed != true || !context.mounted) return;
  await ref.read(musicScanJobControllerProvider.notifier).startScan();
  if (!context.mounted) return;
  final scan = ref.read(musicScanJobControllerProvider);
  if (scan.errorMessage != null) {
    showDesktopToast(
      context,
      scan.errorMessage!,
      kind: DesktopToastKind.error,
      icon: DesktopIcons.info,
    );
  } else {
    showDesktopToast(context, l10n.musicScanQueued, icon: DesktopIcons.check);
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.title, required this.detail, this.trailing});

  final String title;
  final String detail;
  final Widget? trailing;

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
                Text(title, style: DesktopType.bodyStrong(skin.text)),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.caption(skin.text3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}
