part of 'profile_page.dart';

/// 个人中心托管移动形态（样例 ProfilePage）：模块横幅 + 分组行；
/// 全部二级视图均为环境皮肤原生移动形态（个人信息/外观/安全/会话/
/// 通知偏好/服务器/关于），不再复用桌面工位面板。
class ProfileMobileView extends ConsumerStatefulWidget {
  const ProfileMobileView({super.key, this.initialSection});

  final String? initialSection;

  @override
  ConsumerState<ProfileMobileView> createState() => _ProfileMobileViewState();
}

class _ProfileMobileViewState extends ConsumerState<ProfileMobileView> {
  ProfileSection? _section;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSection;
    if (initial != null && initial.isNotEmpty) {
      _section = ProfileSection.parse(initial);
    }
  }

  void _openSection(ProfileSection section) {
    setState(() => _section = section);
  }

  /// 进入账户空间时作废两份 keepAlive 数据源：会话列表与通知类型字典。
  ///
  /// 外观/语言/字号偏好不在此列，它们已由 preference_sync_handler 的推送路径
  /// 同步，再挂一次进入刷新就是重复控制；两步验证状态是 autoDispose，分区打开
  /// 时自会取新。这里只作废、不主动发请求：账户子视图是页内状态，未被监听时
  /// invalidate 仅清缓存，等下一次打开分区再取新值。
  void _invalidateCachedFeeds() {
    ref.invalidate(userSessionsProvider);
    ref.invalidate(notificationTypesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(authSessionProvider).value?.user;
    final displayName =
        user?.displayName ?? user?.username ?? l10n.profileUnknownUser;
    final email = user?.email ?? l10n.profileEmailNotSet;
    final role = user?.role ?? 'MEMBER';
    final avatarUrl = user?.avatarUrl;
    final roleLabel = switch (role) {
      'SUPER_ADMIN' => l10n.profileRoleSuperAdmin,
      'ADMIN' => l10n.profileRoleAdmin,
      _ => l10n.profileRoleMember,
    };
    return ModuleEntryRefreshListener(
      modulePath: '/profile',
      onRefresh: _invalidateCachedFeeds,
      child: PopScope(
        // 账户子视图（资料/通知/2FA/会话…）是页内状态不是路由：一次侧滑先关
        // 子视图，再一次才离开账户页。判据与页头返回钮同一条。
        canPop: _section == null,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          setState(() => _section = null);
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 650),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MobileModuleHeader(
                      title: displayName,
                      subtitle: '$email · $roleLabel',
                      onBack: () {
                        if (_section != null) {
                          setState(() => _section = null);
                          return;
                        }
                        Navigator.of(context).maybePop();
                      },
                      actions: [
                        _ProfileAvatarChip(
                          avatarUrl: avatarUrl,
                          name: displayName,
                          semanticLabel: l10n.profileRowAccountInfo,
                          onTap: () => _openSection(ProfileSection.account),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                    Expanded(
                      child:
                          _section == null
                              ? _buildGroupList(context, l10n)
                              : _buildSectionBody(context, l10n, _section!),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 分组行列表（样例 notif-toggle-row 结构 + 分组眉标）。
  Widget _buildGroupList(BuildContext context, AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _PmGroupLabel(l10n.profileGroupAppearance),
        _PmRow(
          icon: Icons.palette_outlined,
          label: l10n.profileRowTheme,
          subtitle: l10n.profileSectionAppearanceSubtitle,
          onTap: () => _openSection(ProfileSection.appearance),
        ),
        _PmGroupLabel(l10n.profileGroupSecurity),
        _PmRow(
          icon: Icons.person_outline_rounded,
          label: l10n.profileRowAccountInfo,
          subtitle: l10n.profileAccountSubtitle,
          onTap: () => _openSection(ProfileSection.account),
        ),
        _PmRow(
          icon: Icons.shield_outlined,
          label: l10n.profileRowSecurity,
          subtitle: l10n.profileSectionSecuritySubtitle,
          onTap: () => _openSection(ProfileSection.security),
        ),
        _PmRow(
          icon: Icons.notifications_outlined,
          label: l10n.profileRowNotifications,
          subtitle: l10n.profileSectionNotificationsSubtitle,
          onTap: () => _openSection(ProfileSection.notifications),
        ),
        _PmGroupLabel(l10n.profileGroupServer),
        _PmRow(
          icon: Icons.dns_outlined,
          label: l10n.profileRowServer,
          subtitle: l10n.profileSectionServerSubtitle,
          onTap: () => _openSection(ProfileSection.server),
        ),
        _PmGroupLabel(l10n.profileGroupAbout),
        _PmRow(
          icon: Icons.info_outline_rounded,
          label: l10n.profileRowAbout,
          subtitle: l10n.profileSectionAboutSubtitle,
          onTap: () => _openSection(ProfileSection.about),
        ),
        const SizedBox(height: 28),
        _PmSignOutButton(
          onTap: () => ref.read(authSessionProvider.notifier).clearSession(),
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

  Widget _buildSectionBody(
    BuildContext context,
    AppLocalizations l10n,
    ProfileSection section,
  ) {
    return switch (section) {
      ProfileSection.account => const _PmAccountSection(),
      ProfileSection.appearance => const _PmAppearanceSection(),
      ProfileSection.security => const _PmSecuritySection(),
      ProfileSection.notifications => const _PmNotificationsSection(),
      ProfileSection.server => const _PmServerSection(),
      ProfileSection.about => const _PmAboutSection(),
    };
  }
}

// ── 通用件 ─────────────────────────────────────────────────────────────

/// 分组眉标（样例 `.notif-group`）。
class _PmGroupLabel extends StatelessWidget {
  const _PmGroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 9, // ignore: font_size_whitelist
          // 样例浅态第 5 层给 `.notif-group` 的 line-height: 1.45 在两极性都成立
          // （暗态没有任何规则声明行高），字号则两态都是 9px。
          height: 1.45,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w700,
          color: context.env.groupLabelInk,
        ),
      ),
    );
  }
}

/// 设置行（样例 `.notif-toggle-row`）：图标舱 + 标题/副题 + 尾部槽
/// （chevron/开关/自定义），尺寸与字号按该类的最终声明取值。
class _PmRow extends StatelessWidget {
  const _PmRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = context.env.accentInk;
    // InkWell 自带 onTap 语义节点，行内标题/副题文本即读屏标签，
    // 这里不再叠加 Semantics，避免同一行出现两个可聚焦节点。
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.env.line07)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.env.settingIconBg,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11, // ignore: font_size_whitelist
                        fontWeight: FontWeight.w600,
                        color: context.env.ink,
                      ),
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
              if (trailing != null) ...[
                const SizedBox(width: 10),
                trailing!,
              ] else if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: context.env.inkFaint,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 酸绿小开关（样例 env-switch 的共享件薄封装）。
class _PmSwitch extends StatelessWidget {
  const _PmSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MobileEnvSwitch(value: value, onChanged: onChanged);
  }
}

/// 退出登录（样例 sign-out：整宽描边钮）。
class _PmSignOutButton extends StatelessWidget {
  const _PmSignOutButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: context.env.statusDanger,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: context.env.statusDanger.withValues(alpha: 0.22),
          ),
        ),
      ),
      child: Text(
        AppLocalizations.of(context).coreSignOut,
        style: const TextStyle(
          fontSize: 12, // ignore: font_size_whitelist
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 环境输入框（玻璃底 r12 + 酸绿聚焦描边）。
///
/// 以 `TextFormField` 呈现：校验依赖外层 [Form]，非法输入在框下内联
/// 提示；`maxLength` 自带计数文案已关闭，只保留环境字段的单行高度。
class _PmTextField extends StatelessWidget {
  const _PmTextField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.textInputAction,
    this.autofocus = false,
    this.maxLength,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final int? maxLength;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9, // ignore: font_size_whitelist
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: context.env.inkFaint,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          autofocus: autofocus,
          maxLength: maxLength,
          validator: validator,
          style: TextStyle(
            fontSize: 13, // ignore: font_size_whitelist
            color: context.env.ink,
          ),
          decoration: InputDecoration(
            isCollapsed: true,
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 12,
            ),
            filled: true,
            fillColor: context.env.line07,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.env.line09),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.env.line09),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.env.accentInk, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// 酸绿主按钮（样例 accent-square-btn）。
class _PmPrimaryButton extends StatelessWidget {
  const _PmPrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: context.env.accent,
        foregroundColor: context.env.onAccent,
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12, // ignore: font_size_whitelist
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── 二级视图 ───────────────────────────────────────────────────────────

/// 个人信息：头像 + 显示名称/邮箱编辑。
class _PmAccountSection extends ConsumerStatefulWidget {
  const _PmAccountSection();

  @override
  ConsumerState<_PmAccountSection> createState() => _PmAccountSectionState();
}

class _PmAccountSectionState extends ConsumerState<_PmAccountSection> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authSessionProvider).value?.user;
    _name = TextEditingController(
      text: user?.displayName ?? user?.username ?? '',
    );
    _email = TextEditingController(text: user?.email ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final l10n = AppLocalizations.of(context);
    final service = ref.read(profileCommandServiceProvider);
    final result = await FilePick.pickImages();
    if (!mounted || result.isEmpty) {
      return;
    }
    final file = result.first;
    final bytes = await file.readBytes();
    if (!mounted || bytes.isEmpty) {
      return;
    }
    final extension = file.extension;
    if (extension == null ||
        !['jpg', 'jpeg', 'png', 'webp'].contains(extension)) {
      showOmniFeedback(context, l10n.profileAvatarFormatError);
      return;
    }
    if (bytes.length > FileSizeThresholds.avatarUploadMaxBytes) {
      showOmniFeedback(context, l10n.profileAvatarSizeError);
      return;
    }
    try {
      await service.uploadAvatar(bytes, file.name);
      if (!mounted) {
        return;
      }
      await ref.read(authSessionProvider.notifier).reloadProfile();
      if (!mounted) {
        return;
      }
      showOmniFeedback(context, l10n.profileAvatarSuccess);
    } on Exception {
      if (!mounted) {
        return;
      }
      showOmniFeedback(
        context,
        l10n.profileAvatarFailed,
        severity: OmniFeedbackSeverity.error,
      );
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    // 空值与非法格式先在框内内联提示，不打后端。
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(profileCommandServiceProvider)
          .updateProfile(
            displayName: _name.text.trim(),
            email: _email.text.trim(),
          );
      if (!mounted) {
        return;
      }
      await ref.read(authSessionProvider.notifier).reloadProfile();
      if (!mounted) {
        return;
      }
      showOmniFeedback(context, l10n.profileUpdateSuccess);
    } on Exception {
      if (!mounted) {
        return;
      }
      showOmniFeedback(
        context,
        l10n.profileUpdateFailed,
        severity: OmniFeedbackSeverity.error,
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(authSessionProvider).value?.user;
    final avatarUrl = user?.avatarUrl;
    final displayName =
        user?.displayName ?? user?.username ?? l10n.profileUnknownUser;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Center(
            child: Column(
              children: [
                Semantics(
                  button: true,
                  label: l10n.profileChangeAvatar,
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: _ProfileAvatarChip(
                      avatarUrl: avatarUrl,
                      name: displayName,
                      size: 76,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.profileChangeAvatar,
                  style: TextStyle(
                    fontSize: 10, // ignore: font_size_whitelist
                    fontWeight: FontWeight.w600,
                    color: context.env.accentInk,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _PmTextField(
            label: l10n.profileDisplayNameField,
            controller: _name,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            maxLength: ProfileEditDialog.displayNameMaxLength,
            // 分区进入不自动聚焦：该视图还承担头像更换，软键盘会遮住首屏。
            autofocus: false,
            validator:
                (value) =>
                    ProfileEditDialog.validateDisplayName(context, value),
          ),
          const SizedBox(height: 14),
          _PmTextField(
            label: l10n.profileEmailField,
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            maxLength: ProfileEditDialog.emailMaxLength,
            validator:
                (value) => ProfileEditDialog.validateEmail(context, value),
          ),
          const SizedBox(height: 22),
          _PmPrimaryButton(
            label: l10n.profileSaveChanges,
            onPressed: _saving ? null : () => unawaited(_save()),
          ),
        ],
      ),
    );
  }
}

/// 主题与外观：主题模式 + 语言 + 字号（等分三列的选项组）。
class _PmAppearanceSection extends ConsumerWidget {
  const _PmAppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final themeMode = ref.watch(appearanceControllerProvider);
    final languageCode = ref.watch(localeControllerProvider);
    final fontScalePreset = ref.watch(fontScaleControllerProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _PmGroupLabel(l10n.profileThemeLabel),
        MobileAppearanceOptions<ThemeMode>(
          values: ThemeMode.values,
          selected: themeMode,
          semanticLabel: l10n.profileThemeLabel,
          labelBuilder:
              (mode) => switch (mode) {
                ThemeMode.system => l10n.settingsThemeSystem,
                ThemeMode.light => l10n.settingsThemeLight,
                ThemeMode.dark => l10n.settingsThemeDark,
              },
          onSelected:
              (mode) => ref
                  .read(appearanceControllerProvider.notifier)
                  .setThemeMode(mode),
        ),
        const SizedBox(height: 20),
        _PmGroupLabel(l10n.profileLanguageLabel),
        MobileAppearanceOptions<String>(
          values: const ['zh', 'en'],
          selected: languageCode,
          semanticLabel: l10n.profileLanguageLabel,
          labelBuilder: (code) => code == 'zh' ? '中文' : 'English',
          onSelected:
              (code) =>
                  ref.read(localeControllerProvider.notifier).setLanguage(code),
        ),
        const SizedBox(height: 20),
        _PmGroupLabel(l10n.profileFontScaleLabel),
        MobileAppearanceOptions<FontScalePreset>(
          values: FontScalePreset.values,
          selected: fontScalePreset,
          semanticLabel: l10n.profileFontScaleLabel,
          labelBuilder: (preset) => fontScalePresetLabel(l10n, preset),
          onSelected:
              (preset) => unawaited(
                ref
                    .read(fontScaleControllerProvider.notifier)
                    .setPreset(preset),
              ),
        ),
      ],
    );
  }
}

/// 头像圆片（有图用图，无图取首字母）。
///
/// [onTap] 非空时该圆片即为按钮，读屏必须能播报动作含义，故同时要求
/// [semanticLabel]（例如「个人信息」或「更换头像」）。
class _ProfileAvatarChip extends StatelessWidget {
  const _ProfileAvatarChip({
    required this.avatarUrl,
    required this.name,
    this.size = 40,
    this.onTap,
    this.semanticLabel,
  });

  final String? avatarUrl;
  final String name;
  final double size;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    final initials =
        name.trim().isNotEmpty
            ? name.trim().characters.first.toUpperCase()
            : '?';
    final body = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.env.avatarBg,
        shape: BoxShape.circle,
      ),
      child:
          url != null && url.isNotEmpty
              ? ClipOval(
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder:
                      (_, _, _) => Center(
                        child: Text(
                          initials,
                          style: TextStyle(
                            fontSize:
                                size * 0.33, // ignore: font_size_whitelist
                            fontWeight: FontWeight.w700,
                            color: context.env.avatarFg,
                          ),
                        ),
                      ),
                ),
              )
              : Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: size * 0.33, // ignore: font_size_whitelist
                    fontWeight: FontWeight.w700,
                    color: context.env.avatarFg,
                  ),
                ),
              ),
    );
    if (onTap == null) {
      return body;
    }
    // 头像圆片无文字标签：补按钮角色与动作名称，读屏才能说出这是按钮。
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: body,
      ),
    );
  }
}
