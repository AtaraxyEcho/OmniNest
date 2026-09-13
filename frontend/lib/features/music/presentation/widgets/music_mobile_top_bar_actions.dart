import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_deck_source_selection_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';
import 'package:omninest/features/music/presentation/widgets/music_platform_login.dart';

/// 在应用级移动顶部栏中提供音乐来源和平台账号操作。
class MusicMobileTopBarActions extends ConsumerWidget {
  const MusicMobileTopBarActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(musicPlatformLibraryProvider).asData?.value;
    final sources = ref.watch(musicDeckSourceSelectionProvider);
    final availableSources = <MusicPlatform>[
      MusicPlatform.local,
      for (final status
          in platform?.connectedStatuses ?? const <MusicPlatformStatus>[])
        MusicPlatform.fromApiValue(status.platform),
    ];
    final hasFilteredSource = sources.length != availableSources.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<MusicPlatform>(
          tooltip: AppLocalizations.of(context).musicDeckSources,
          onSelected:
              ref.read(musicDeckSourceSelectionProvider.notifier).toggle,
          itemBuilder:
              (context) => availableSources
                  .map(
                    (source) => CheckedPopupMenuItem<MusicPlatform>(
                      value: source,
                      checked: sources.contains(source),
                      child: MusicDeckSourceBadge(platform: source),
                    ),
                  )
                  .toList(growable: false),
          icon: Badge(
            isLabelVisible: hasFilteredSource,
            smallSize: 7,
            child: Icon(
              Icons.tune_rounded,
              size: 22,
              color: context.musicColors.onSurface,
            ),
          ),
          color: context.musicColors.surfaceContainerHigh,
        ),
        IconButton(
          tooltip: AppLocalizations.of(context).musicDeckManageAccounts,
          onPressed: () => _openAccounts(context),
          icon: Badge(
            isLabelVisible: (platform?.connectedStatuses.length ?? 0) > 0,
            smallSize: 7,
            child: Icon(
              Icons.cloud_sync_outlined,
              size: 22,
              color: context.musicColors.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openAccounts(BuildContext context) async {
    final container = ProviderScope.containerOf(context, listen: false);
    await PlatformLoginSheet.show(context);
    if (!context.mounted) {
      return;
    }
    // 关闭面板仅轻量刷新账号信息；曲库全量刷新由登录成功路径触发。
    unawaited(
      container.read(musicCenterControllerProvider.notifier).loadPlatformInfo(),
    );
  }
}
