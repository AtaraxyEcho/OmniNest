import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/server/server_config_controller.dart';

/// 服务器与连接面板：展示当前生效地址（自定义/预置）并发起更换流程。
///
/// 更换 = 退出登录（authSession 用户变化自动触发业务 provider 全量重置）
/// → 清除自定义配置（回落预置或未配置）→ 进入首启引导页重新录入。
class ProfileServerPanel extends ConsumerWidget {
  const ProfileServerPanel({super.key});

  Future<void> _confirmAndChange(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.serverPanelChangeTitle),
            content: Text(l10n.serverPanelChangeBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.serverPanelChangeCancel),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.serverPanelChangeConfirm),
              ),
            ],
          ),
    );
    if (confirmed != true) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.profileSectionServer,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.serverPanelCurrent,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        environment?.apiBaseUrl ?? '-',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      badgeText,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: scheme.primary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => _confirmAndChange(context, ref),
          icon: const Icon(Icons.swap_horiz_rounded),
          label: Text(l10n.serverPanelChange),
        ),
      ],
    );
  }
}
