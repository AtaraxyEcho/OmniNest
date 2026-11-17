part of 'admin_users_page.dart';

/// 用户管理的桌面排版（样例 `AdminIdentity.tsx` 的 Identity）：
/// 一张卡里是卡头（用户数 + 新建）、工具栏（搜索 + 角色筛选）、用户行与翻页条。
/// 动作复用同一批对话框与控制器，不复制业务逻辑。
class _DesktopUsersPanel extends ConsumerStatefulWidget {
  const _DesktopUsersPanel({required this.state});

  final AdminUserState state;

  @override
  ConsumerState<_DesktopUsersPanel> createState() => _DesktopUsersPanelState();
}

class _DesktopUsersPanelState extends ConsumerState<_DesktopUsersPanel> {
  late final TextEditingController _search = TextEditingController(
    text: widget.state.query,
  );

  /// 最后一次由输入框发出的查询串。控制器有 300ms 防抖，不能用
  /// `state.query` 反过来覆盖正在输入的内容；只有「外部改了筛选」
  /// （清空筛选、顶栏搜索）时才把文本同步回来。
  late String _sent = widget.state.query;

  @override
  void didUpdateWidget(covariant _DesktopUsersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.query != _sent) {
      _sent = widget.state.query;
      _search.text = _sent;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final controller = ref.read(adminUserControllerProvider.notifier);
    final state = widget.state;
    final users = state.users;
    final filtered = state.query.isNotEmpty || state.roleFilter != 'ALL';

    return AdminCard(
      title: l10n.adminUsers,
      count: state.totalElements,
      action: DesktopButton(
        label: l10n.adminCreateUser,
        icon: DesktopIcons.plus,
        variant: DesktopButtonVariant.soft,
        onPressed:
            () => showWorkstationDialog(
              context: context,
              builder: (context) => const _CreateUserDialog(),
            ),
      ),
      childGap: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 280,
                child: DesktopTextField(
                  keyName: 'admin-users-search',
                  controller: _search,
                  hint: l10n.adminSearchUsers,
                  prefixIcon: DesktopIcons.search,
                  height: DesktopMetrics.searchBoxHeight,
                  onChanged: (value) {
                    _sent = value;
                    controller.setSearchTerm(value);
                  },
                ),
              ),
              const SizedBox(width: 14),
              Flexible(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      DesktopChipButton(
                        label: l10n.adminAllRoles,
                        selected: state.roleFilter == 'ALL',
                        onTap: () => controller.setRoleFilter('ALL'),
                      ),
                      for (final role in const [
                        AdminRoles.superAdmin,
                        AdminRoles.admin,
                        AdminRoles.member,
                        AdminRoles.guest,
                      ])
                        DesktopChipButton(
                          label: adminRoleDisplayName(l10n, role),
                          selected: state.roleFilter == role,
                          onTap: () => controller.setRoleFilter(role),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (users.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      filtered ? l10n.adminNoMatch : l10n.adminNoUsers,
                      style: DesktopType.caption(skin.text3),
                    ),
                    if (filtered) ...[
                      const SizedBox(height: 4),
                      DesktopLink(
                        label: l10n.adminClearFilters,
                        onPressed: () {
                          _search.clear();
                          _sent = '';
                          controller.clearFilters();
                        },
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            for (var i = 0; i < users.length; i++)
              _DesktopUserRow(user: users[i], first: i == 0),
          AdminPager(
            page: state.page,
            totalPages: state.totalPages,
            summary: l10n.adminUsersTotal(state.totalElements),
            onPageChanged: controller.setPage,
          ),
        ],
      ),
    );
  }
}

class _DesktopUserRow extends ConsumerWidget {
  const _DesktopUserRow({required this.user, required this.first});

  final AdminUser user;

  /// 样例 `.tr:first-child { border-top: 0 }`：首行不再画一条重复的分隔线。
  final bool first;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final active = user.status == AdminUserStatus.active;
    final meta = <String>[
      '@${user.username}',
      if (user.twoFactorEnabled) '2FA',
      if (_shortDate(user.createdAt).isNotEmpty) _shortDate(user.createdAt),
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: skin.line)),
      ),
      child: Row(
        children: [
          _UserAvatar(
            imageUrl: user.avatarUrl,
            fallbackText: user.title,
            size: 30,
            circle: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.rowTitle(skin.text),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopType.caption(skin.text3),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 168,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final role
                    in user.roles.isEmpty ? {user.role} : user.roles)
                  DesktopChip(adminRoleDisplayName(l10n, role)),
              ],
            ),
          ),
          SizedBox(
            width: 150,
            child: _DesktopQuotaMeter(
              user: user,
              onTap:
                  () => showWorkstationDialog(
                    context: context,
                    builder: (context) => _EditQuotaDialog(user: user),
                  ),
            ),
          ),
          SizedBox(
            width: user.isSuperAdmin ? 132 : 108,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (user.isSuperAdmin)
                  DesktopChip(l10n.adminUserProtected)
                else ...[
                  DesktopIconButton(
                    icon: DesktopIcons.edit,
                    size: 28,
                    iconSize: 14,
                    tooltip: l10n.adminEditUser,
                    onPressed:
                        () => showDesktopDrawer<bool>(
                          context,
                          width: 440,
                          builder: (_) => _EditUserDrawer(user: user),
                        ),
                  ),
                  if (user.twoFactorEnabled)
                    DesktopIconButton(
                      icon: DesktopIcons.lock,
                      size: 28,
                      iconSize: 14,
                      tooltip: l10n.adminResetTwoFactor,
                      onPressed:
                          () => _confirmResetTwoFactor(context, ref, user),
                    ),
                  DesktopIconButton(
                    icon: DesktopIcons.trash,
                    size: 28,
                    iconSize: 14,
                    tooltip: l10n.adminDeleteUser,
                    color: skin.bad,
                    onPressed: () => _confirmDeleteUser(context, ref, user),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 38,
            child: Align(
              alignment: Alignment.centerRight,
              child:
                  user.isSuperAdmin
                      ? const SizedBox.shrink()
                      : DesktopToggle(
                        value: active,
                        label: user.title,
                        onChanged:
                            (_) => _confirmToggleStatus(context, ref, user),
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 配额格：4px 进度条 + 「已用 / 上限」，整块可点开配额对话框（样例 `.quota`）。
class _DesktopQuotaMeter extends StatelessWidget {
  const _DesktopQuotaMeter({required this.user, required this.onTap});

  final AdminUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final unlimited = user.quotaBytes <= 0;
    final ratio = user.quotaUsage.clamp(0.0, 1.0);
    final tone = ratio > 0.8 ? skin.warn : skin.accent;
    return DesktopHover(
      builder:
          (context, hovered) => GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 4,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ColoredBox(color: skin.raise3),
                          ),
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: unlimited ? 0 : ratio,
                                child: ColoredBox(
                                  color:
                                      hovered
                                          ? Color.lerp(tone, skin.text, 0.12)!
                                          : tone,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    unlimited
                        ? '${formatFileSize(user.usedBytes)} / ${AppLocalizations.of(context).adminQuotaUnlimited}'
                        : '${formatFileSize(user.usedBytes)} / ${formatFileSize(user.quotaBytes)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesktopType.micro(skin.text3),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

Future<void> _confirmToggleStatus(
  BuildContext context,
  WidgetRef ref,
  AdminUser user,
) async {
  final l10n = AppLocalizations.of(context);
  final disabling = user.status == AdminUserStatus.active;
  final confirmed = await showWorkstationConfirmDialog(
    context,
    title:
        disabling
            ? l10n.adminUserDisableConfirmTitle
            : l10n.adminUserEnableConfirmTitle,
    message:
        disabling
            ? l10n.adminUserDisableConfirmMessage(user.title)
            : l10n.adminUserEnableConfirmMessage(user.title),
    confirmLabel: disabling ? l10n.adminDisable : l10n.adminEnabled,
    destructive: disabling,
  );
  if (!confirmed || !context.mounted) {
    return;
  }
  try {
    await ref
        .read(adminUserControllerProvider.notifier)
        .updateUserStatus(
          user.id,
          disabling ? AdminUserStatus.disabled : AdminUserStatus.active,
        );
  } catch (error) {
    if (context.mounted) {
      showOmniFeedback(
        context,
        userFacingErrorText(error, l10n: l10n),
        severity: OmniFeedbackSeverity.error,
      );
    }
  }
}

Future<void> _confirmResetTwoFactor(
  BuildContext context,
  WidgetRef ref,
  AdminUser user,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showWorkstationConfirmDialog(
    context,
    title: l10n.adminResetTwoFactor,
    message: l10n.adminResetTwoFactorConfirmMessage(user.title),
    confirmLabel: l10n.adminResetTwoFactor,
    destructive: true,
  );
  if (!confirmed || !context.mounted) {
    return;
  }
  try {
    await ref
        .read(adminUserControllerProvider.notifier)
        .resetTwoFactor(user.id);
    if (context.mounted) {
      showOmniFeedback(
        context,
        l10n.adminResetTwoFactorSuccess,
        severity: OmniFeedbackSeverity.success,
      );
    }
  } catch (error) {
    if (context.mounted) {
      showOmniFeedback(
        context,
        userFacingErrorText(error, l10n: l10n),
        severity: OmniFeedbackSeverity.error,
      );
    }
  }
}

Future<void> _confirmDeleteUser(
  BuildContext context,
  WidgetRef ref,
  AdminUser user,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showWorkstationDestructiveConfirm(
    context,
    title: l10n.adminDeleteUser,
    message: l10n.adminDeleteUserConfirmMessage(user.title),
    confirmPhrase: user.username,
    confirmLabel: l10n.adminDeleteUser,
  );
  if (!confirmed || !context.mounted) {
    return;
  }
  try {
    await ref.read(adminUserControllerProvider.notifier).deleteUser(user.id);
  } catch (error) {
    if (context.mounted) {
      showOmniFeedback(
        context,
        userFacingErrorText(error, l10n: l10n),
        severity: OmniFeedbackSeverity.error,
      );
    }
  }
}

String _shortDate(String? value) {
  if (value == null || value.isEmpty) {
    return '';
  }
  final parsed = DateTime.tryParse(value)?.toLocal();
  if (parsed == null) {
    return '';
  }
  final month = parsed.month.toString().padLeft(2, '0');
  final day = parsed.day.toString().padLeft(2, '0');
  return '${parsed.year}-$month-$day';
}
