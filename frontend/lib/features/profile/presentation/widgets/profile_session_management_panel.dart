import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/features/profile/application/profile_controller.dart';
import 'package:omninest/features/profile/domain/user_session.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_section_card.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';

/// 活跃登录会话表：设备 / IP / 状态 / 操作，当前会话不可撤销。
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
    final l10n = AppLocalizations.of(context);
    final content = _SessionContent(
      sessionsAsync: ref.watch(userSessionsProvider),
    );
    if (!widget.framed) {
      return Padding(padding: const EdgeInsets.all(20), child: content);
    }
    return ProfileSectionCard(
      title: l10n.profileActiveSessionsTitle,
      subtitle: l10n.profileSessionManagementSubtitle,
      child: content,
    );
  }
}

class _SessionContent extends StatelessWidget {
  const _SessionContent({required this.sessionsAsync});

  final AsyncValue<List<UserSession>> sessionsAsync;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return sessionsAsync.when(
      loading:
          () => const SizedBox(
            height: 88,
            child: Center(child: CircularProgressIndicator.adaptive()),
          ),
      error:
          (_, _) => SizedBox(
            height: 72,
            child: Center(child: Text(l10n.profileSessionsLoadFailed)),
          ),
      data: (sessions) {
        if (sessions.isEmpty) {
          return SizedBox(
            height: 72,
            child: Center(
              child: Text(
                l10n.profileNoSessions,
                style: TextStyle(
                  fontSize: AppTypography.bodyMedium,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            // 三档渐进：窄容器（移动弹层）降级为卡片流；中档隐藏有效期与
            // 最后活跃两个明细列保对齐；宽档全列铺开。
            final width = constraints.maxWidth;
            if (width < _kCompactBreakpoint) {
              return Column(
                children: [
                  for (var index = 0; index < sessions.length; index++) ...[
                    if (index > 0)
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: scheme.outlineVariant,
                      ),
                    _SessionRow(session: sessions[index], compact: true),
                  ],
                ],
              );
            }
            final showDetailColumns = width >= _kFullColumnsBreakpoint;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SessionTableHeader(showDetailColumns: showDetailColumns),
                for (var index = 0; index < sessions.length; index++) ...[
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: scheme.outlineVariant,
                  ),
                  _SessionRow(
                    session: sessions[index],
                    showDetailColumns: showDetailColumns,
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _SessionTableHeader extends StatelessWidget {
  const _SessionTableHeader({required this.showDetailColumns});

  /// 是否渲染有效期与最后活跃两个明细列（宽档全开）。
  final bool showDetailColumns;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Expanded 只能作为 Flex 直接子级，这里返回纯 Text，由 Row 统一布局。
    Widget header(String label, {TextAlign align = TextAlign.left}) {
      return Text(
        label.toUpperCase(),
        textAlign: align,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: AppTypography.monoFamily,
          fontFamilyFallback: AppTypography.monoFamilyFallback,
          fontSize: AppTypography.labelMicro,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
        ),
      );
    }

    Widget cell(double width, String label) =>
        SizedBox(width: width, child: header(label));

    return Row(
      children: [
        cell(_kDeviceColWidth, l10n.profileSessionDeviceColumn),
        const SizedBox(width: 16),
        cell(_kIpColWidth, l10n.profileSessionIpColumn),
        const SizedBox(width: 16),
        cell(_kTimeColWidth, l10n.profileSessionLoginTimeColumn),
        if (showDetailColumns) ...[
          const SizedBox(width: 16),
          cell(_kTimeColWidth, l10n.profileSessionExpiresColumn),
          const SizedBox(width: 16),
          cell(_kTimeColWidth, l10n.profileSessionLastActiveColumn),
        ],
        const SizedBox(width: 16),
        cell(_kStatusColWidth, l10n.profileSessionStatusColumn),
        const Spacer(),
        SizedBox(
          width: _kActionColWidth,
          child: header(
            l10n.profileSessionActionColumn,
            align: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// 桌面表格列宽：定宽列保证行间对齐，Spacer 吸收富余宽度。
const double _kDeviceColWidth = 230;
const double _kIpColWidth = 150;
const double _kTimeColWidth = 120;
const double _kStatusColWidth = 100;
const double _kActionColWidth = 96;

/// 明细列（有效期 + 最后活跃）全开断点：全列含间距约 1018px。
const double _kFullColumnsBreakpoint = 1040;

/// compact 卡片流断点：核心五列含间距约 738px，低于该宽度降级。
const double _kCompactBreakpoint = 760;

/// 会话行：平台图标 + 设备名 + 平台代码 / IP / 登录时间 /（有效期、
/// 最后活跃）/ 状态徽章 / 操作；明细列仅宽档渲染。
class _SessionRow extends ConsumerWidget {
  const _SessionRow({
    required this.session,
    this.compact = false,
    this.showDetailColumns = false,
  });

  final UserSession session;
  final bool compact;

  /// 是否渲染有效期与最后活跃两个明细列（与表头档位一致）。
  final bool showDetailColumns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final nameText = Text(
      session.effectiveDeviceName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: AppTypography.bodyMedium,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
    );
    final monoSmall = TextStyle(
      fontFamily: AppTypography.monoFamily,
      fontFamilyFallback: AppTypography.monoFamilyFallback,
      fontSize: AppTypography.labelSmall,
      color: scheme.onSurfaceVariant,
    );
    // IPv6 等长地址在列内截断，悬停可见全文。
    final ipText = Tooltip(
      message: session.ipAddress,
      child: Text(
        session.ipAddress,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: monoSmall,
      ),
    );
    final loginTimeText = Text(
      _shortLoginTime(session.issuedAt),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: monoSmall,
    );
    final expiresText = Text(
      _shortLoginTime(session.expiresAt),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: monoSmall.copyWith(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
      ),
    );
    final lastActiveText = Text(
      _shortLoginTime(session.lastActiveAt),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: monoSmall,
    );
    // 平台代码徽标：mono 方括号小签，与设备名同行。
    final platformTag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        color: scheme.surfaceContainerLowest,
      ),
      child: Text(
        '[${_platformCode(session.clientPlatform)}]',
        style: TextStyle(
          fontFamily: AppTypography.monoFamily,
          fontFamilyFallback: AppTypography.monoFamilyFallback,
          fontSize: AppTypography.labelMicro,
          letterSpacing: 0.8,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
    final icon = Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        color: scheme.surfaceContainerLowest,
      ),
      child: Icon(
        _platformIcon(session.clientPlatform),
        size: 14,
        color: scheme.onSurfaceVariant,
      ),
    );
    final status = _SessionStatus(session: session);
    final revoke = _SessionRevokeButton(session: session);

    if (compact) {
      // 窄容器（移动弹层）合并为单列三行：设备名 / IP·登录时间 / 有效期。
      final loginInfo = Text(
        '${session.ipAddress} · ${l10n.profileSessionLoginAt(_shortLoginTime(session.issuedAt))}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: monoSmall,
      );
      final expiresInfo = Text(
        l10n.profileSessionExpiresAt(_shortLoginTime(session.expiresAt)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: monoSmall.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
        ),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  nameText,
                  const SizedBox(height: 3),
                  loginInfo,
                  const SizedBox(height: 2),
                  expiresInfo,
                ],
              ),
            ),
            const SizedBox(width: 12),
            status,
            const SizedBox(width: 8),
            revoke,
          ],
        ),
      );
    }
    return _HoverRow(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: _kDeviceColWidth,
              child: Row(
                children: [
                  icon,
                  const SizedBox(width: 8),
                  Expanded(child: nameText),
                  const SizedBox(width: 6),
                  platformTag,
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(width: _kIpColWidth, child: ipText),
            const SizedBox(width: 16),
            SizedBox(width: _kTimeColWidth, child: loginTimeText),
            if (showDetailColumns) ...[
              const SizedBox(width: 16),
              SizedBox(width: _kTimeColWidth, child: expiresText),
              const SizedBox(width: 16),
              SizedBox(width: _kTimeColWidth, child: lastActiveText),
            ],
            const SizedBox(width: 16),
            // Align 阻断 tight 约束：徽章按内容收缩，不再铺满整列。
            SizedBox(
              width: _kStatusColWidth,
              child: Align(alignment: Alignment.centerLeft, child: status),
            ),
            const Spacer(),
            SizedBox(
              width: _kActionColWidth,
              child: Align(alignment: Alignment.centerRight, child: revoke),
            ),
          ],
        ),
      ),
    );
  }
}

/// 行悬停：仅底色微亮，保持纯平直角。
class _HoverRow extends StatefulWidget {
  const _HoverRow({required this.child});

  final Widget child;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        color:
            _hovering
                ? scheme.onSurface.withValues(alpha: 0.04)
                : Colors.transparent,
        child: widget.child,
      ),
    );
  }
}

/// 平台代码徽标文案：客户端平台归并为短码。
String _platformCode(String platform) {
  return switch (platform.toLowerCase()) {
    'web' => 'WEB',
    'android' => 'ANDROID',
    'ios' => 'IOS',
    'macos' => 'MACOS',
    'windows' => 'WIN',
    'linux' => 'LINUX',
    'desktop' => 'DESKTOP',
    _ => 'CLIENT',
  };
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

class _SessionStatus extends StatelessWidget {
  const _SessionStatus({required this.session});

  final UserSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (session.current) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          color: scheme.surfaceContainer,
        ),
        child: Text(
          l10n.profileSessionCurrent,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppTypography.monoFamily,
            fontFamilyFallback: AppTypography.monoFamilyFallback,
            fontSize: AppTypography.labelMicro,
            letterSpacing: 1.2,
            color: scheme.onSurface,
          ),
        ),
      );
    }
    // 非当前会话：最后活跃信息在独立列承载，此处仅占位保持行对齐。
    return Text(
      '—',
      style: TextStyle(
        fontFamily: AppTypography.monoFamily,
        fontFamilyFallback: AppTypography.monoFamilyFallback,
        fontSize: AppTypography.labelSmall,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}

class _SessionRevokeButton extends ConsumerWidget {
  const _SessionRevokeButton({required this.session});

  final UserSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (session.current) {
      return Text(
        '-',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: AppTypography.labelMedium,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      );
    }
    return WorkstationActionButton(
      label: l10n.profileRevokeSession,
      variant: WorkstationActionButtonVariant.danger,
      onPressed: () => _confirmRevoke(context, ref),
    );
  }

  Future<void> _confirmRevoke(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showWorkstationConfirmDialog(
      context,
      title: l10n.profileRevokeSessionConfirm,
      message: l10n.profileRevokeSessionMessage,
      confirmLabel: l10n.profileRevokeSession,
      destructive: true,
    );
    if (confirmed != true) return;
    try {
      await ref.read(profileCommandServiceProvider).revokeSession(session.id);
      ref.invalidate(userSessionsProvider);
      if (context.mounted) {
        showOmniFeedback(context, l10n.profileSessionRevoked);
      }
    } on Exception {
      if (context.mounted) {
        showOmniFeedback(
          context,
          l10n.profileSessionRevokeFailed,
          severity: OmniFeedbackSeverity.error,
        );
      }
    }
  }
}

/// 会话时间列的紧凑格式：同年省略年份，避免列内截断。
String _shortLoginTime(String isoTime) {
  final dateTime = DateTime.tryParse(isoTime)?.toLocal();
  if (dateTime == null) return isoTime;
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  final now = DateTime.now();
  final date =
      dateTime.year == now.year
          ? '${twoDigits(dateTime.month)}-${twoDigits(dateTime.day)}'
          : '${dateTime.year}-${twoDigits(dateTime.month)}-${twoDigits(dateTime.day)}';
  return '$date ${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}';
}
