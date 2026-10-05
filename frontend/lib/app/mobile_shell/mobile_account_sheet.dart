import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/theme/mobile_env_colors.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/profile/application/profile_controller.dart';

/// 顶栏账户头像：点击打开承载低频系统能力的账户面板。
class MobileAccountAvatar extends ConsumerWidget {
  const MobileAccountAvatar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(userDisplayNameProvider);
    final avatarUrl = ref.watch(userAvatarUrlProvider);
    final online = ref.watch(appOnlineStatusProvider).asData?.value != false;
    final initials =
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    return Tooltip(
      message: AppLocalizations.of(context).accountSheetTitle,
      child: MobilePressable(
        semanticLabel: AppLocalizations.of(context).accountSheetTitle,
        onTap: () => showOmniAccountSheet(context),
        child: SizedBox(
          width: 46,
          height: 46,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                child: ClipOval(
                  child: SizedBox(
                    width: 43,
                    height: 43,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: MobileEnvColors.avatarBg),
                        if (avatarUrl != null && avatarUrl.isNotEmpty)
                          Image.network(
                            avatarUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _initials(initials, 13),
                          )
                        else
                          _initials(initials, 13),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color:
                        online
                            ? MobileEnvColors.accent
                            : MobileEnvColors.white46,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF25302D),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _initials(String initials, double fontSize) {
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          color: MobileEnvColors.avatarFg,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 打开账户面板：头像菜单承载通知、设备、视觉环境与设置等系统能力。
///
/// 面板内容高度封顶 85% 视口并可滚动：矮屏与放大字号下不再溢出。
/// 减弱动效时进出即时完成（noAnimation），面板终态呈现不变。
Future<void> showOmniAccountSheet(BuildContext ownerContext) {
  return showModalBottomSheet<void>(
    context: ownerContext,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    sheetAnimationStyle:
        MotionToken.prefersReduced(ownerContext)
            ? AnimationStyle.noAnimation
            : null,
    builder: (context) => const _OmniAccountSheet(),
  );
}

class _OmniAccountSheet extends ConsumerWidget {
  const _OmniAccountSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: MobileEnvColors.sheetSolid,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: Color(0x21FFFFFF))),
            boxShadow: [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 50,
                offset: Offset(0, -20),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  _SheetHandle(),
                  _AccountProfileRow(),
                  _AccountStatusRow(),
                  _AccountNavRows(),
                  _ManageAccountButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 自绘拖拽把手（36×4 白 22%），替代 Material 默认把手。
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0x38FFFFFF),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _AccountProfileRow extends ConsumerWidget {
  const _AccountProfileRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final name = ref.watch(userDisplayNameProvider);
    final email = profile?.email ?? '';
    final avatarUrl = ref.watch(userAvatarUrlProvider);
    final initials =
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    return MobilePressable(
      semanticLabel: name,
      onTap: () => _closeAnd(context, () => context.push('/profile')),
      child: Container(
        constraints: const BoxConstraints(minHeight: 65),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 50,
                height: 50,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: MobileEnvColors.avatarBg),
                    if (avatarUrl != null && avatarUrl.isNotEmpty)
                      Image.network(
                        avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _initials(initials, 15),
                      )
                    else
                      _initials(initials, 15),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MobileEnvColors.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (email.isNotEmpty)
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MobileEnvColors.inkMuted,
                        fontSize: 10,
                        height: 1.4,
                      ),
                    ),
                ],
              ),
            ),
            const OmniIcon(
              icon: OmniIcons.chevron,
              size: 18,
              color: MobileEnvColors.inkMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _initials(String initials, double fontSize) {
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          color: MobileEnvColors.avatarFg,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AccountStatusRow extends ConsumerWidget {
  const _AccountStatusRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final online = ref.watch(appOnlineStatusProvider).asData?.value != false;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 13),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: MobileEnvColors.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color:
                      online ? MobileEnvColors.accent : MobileEnvColors.white46,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  online
                      ? l10n.accountStatusHealthy
                      : l10n.accountStatusOffline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MobileEnvColors.ink,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            online ? l10n.accountStatusSyncNote : l10n.accountStatusOfflineNote,
            style: const TextStyle(
              color: MobileEnvColors.inkMuted,
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountNavRows extends ConsumerWidget {
  const _AccountNavRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final unread = ref.watch(unreadCountProvider);
    final sessions = ref.watch(userSessionsProvider).asData?.value;
    final backdrop = ref.watch(appBackdropControllerProvider).asData?.value;
    final backdropTitle = backdrop?.selectedBackdrop?.title;
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: MobileEnvColors.line13)),
      ),
      child: Column(
        children: [
          _AccountSheetRow(
            icon: OmniIcons.bell,
            label: l10n.accountEntryNotifications,
            subtitle:
                unread > 0
                    ? l10n.accountEntryNotificationsSub(unread)
                    : l10n.accountEntryNotificationsNone,
            badge: unread > 0 ? (unread > 99 ? '99+' : '$unread') : null,
            onTap:
                () => _closeAnd(context, () => context.push('/notifications')),
          ),
          _AccountSheetRow(
            icon: OmniIcons.device,
            label: l10n.accountEntryDevices,
            subtitle:
                sessions == null
                    ? null
                    : l10n.accountEntryDevicesSub(sessions.length),
            onTap:
                () => _closeAnd(
                  context,
                  () => context.push('/profile?section=security'),
                ),
          ),
          _AccountSheetRow(
            icon: OmniIcons.image,
            label: l10n.accountEntryEnvironment,
            subtitle:
                backdropTitle?.isNotEmpty == true
                    ? backdropTitle
                    : l10n.accountEntryEnvironmentDefault,
            // 移动端改用样例 EnvSettings 全覆盖抽屉（视觉环境专页）。
            onTap: () => _openBackdrop(context),
          ),
          _AccountSheetRow(
            icon: OmniIcons.settings,
            label: l10n.accountEntrySettings,
            subtitle: l10n.accountEntrySettingsSub,
            onTap:
                () => _closeAnd(
                  context,
                  () => context.push('/profile?section=appearance'),
                ),
          ),
        ],
      ),
    );
  }

  void _openBackdrop(BuildContext sheetContext) {
    // 先捕获属主 context 再弹面板（面板自身 pop 后其 context 失活）。
    final ownerContext = sheetContext;
    Navigator.of(sheetContext).pop();
    showMobileEnvSettingsSheet(ownerContext);
  }
}

void _closeAnd(BuildContext sheetContext, void Function() action) {
  // 只弹面板自身（modal 路由）；根导航 pop 会炸掉最后一页。
  Navigator.of(sheetContext).pop();
  action();
}

class _AccountSheetRow extends StatelessWidget {
  const _AccountSheetRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.badge,
  });

  final OmniIconsData icon;
  final String label;

  /// 行副标题（真实数据：未读数 / 设备数 / 壁纸名 / 设置域）。
  final String? subtitle;
  final VoidCallback onTap;

  /// 行尾数量徽标（如未读通知数）。
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return MobilePressable(
      semanticLabel: label,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 61),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x12FFFFFF))),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0x0FFFFFFF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: OmniIcon(
                  icon: icon,
                  size: 18,
                  color: MobileEnvColors.accent,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MobileEnvColors.ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MobileEnvColors.inkMuted,
                          fontSize: 9,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (badge != null) ...[
              Container(
                width: 19,
                height: 19,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: MobileEnvColors.accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: MobileEnvColors.onAccent,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            const OmniIcon(
              icon: OmniIcons.chevron,
              size: 18,
              color: MobileEnvColors.inkMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _ManageAccountButton extends StatelessWidget {
  const _ManageAccountButton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: OutlinedButton(
        onPressed: () => _closeAnd(context, () => context.push('/profile')),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(47),
          foregroundColor: MobileEnvColors.ink,
          backgroundColor: Colors.white.withValues(alpha: 0.07),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(l10n.accountManageAccount),
      ),
    );
  }
}
