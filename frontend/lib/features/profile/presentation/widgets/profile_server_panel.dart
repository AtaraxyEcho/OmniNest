import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/server/server_config_controller.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';

/// 服务器与连接面板：展示当前生效地址（自定义/预置）并发起更换流程。
///
/// 更换 = 退出登录（authSession 用户变化自动触发业务 provider 全量重置）
/// → 清除自定义配置（回落预置或未配置）→ 进入首启引导页重新录入。
class ProfileServerPanel extends ConsumerWidget {
  const ProfileServerPanel({super.key});

  Future<void> _confirmAndChange(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showWorkstationConfirmDialog(
      context,
      title: l10n.serverPanelChangeTitle,
      message: l10n.serverPanelChangeBody,
      confirmLabel: l10n.serverPanelChangeConfirm,
      destructive: true,
    );
    if (!confirmed) {
      return;
    }
    await ref.read(authSessionProvider.notifier).clearSession();
    await ref.read(serverConfigProvider.notifier).clear();
    if (!context.mounted) {
      return;
    }
    context.go('/server-setup?switch=1');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final custom = ref.watch(serverConfigProvider).asData?.value;
    final environment = ref.watch(appEnvironmentProvider);

    final badgeText =
        custom != null
            ? l10n.serverPanelBadgeCustom
            : environment != null
            ? l10n.serverPanelBadgePreset
            : l10n.serverPanelBadgeUnconfigured;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.serverPanelCurrent,
            style: TextStyle(
              fontSize: AppTypography.labelSmall,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  environment?.apiBaseUrl ?? '-',
                  style: TextStyle(
                    fontFamily: AppTypography.monoFamily,
                    fontFamilyFallback: AppTypography.monoFamilyFallback,
                    fontSize: AppTypography.bodyMedium,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  color: scheme.surfaceContainerLowest,
                ),
                child: Text(
                  badgeText.toUpperCase(),
                  style: TextStyle(
                    fontFamily: AppTypography.monoFamily,
                    fontFamilyFallback: AppTypography.monoFamilyFallback,
                    fontSize: AppTypography.labelMicro,
                    letterSpacing: 1.2,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: WorkstationActionButton(
              label: l10n.serverPanelChange,
              icon: Icons.swap_horiz_rounded,
              onPressed: () => _confirmAndChange(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}
