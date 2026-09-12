import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/features/music/application/music_local_preferences_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';

/// 后端约定的在线音质等级从高到低的排序。
const Map<String, int> _musicQualityOrder = <String, int>{
  'jymaster': 0,
  'jyeffect': 1,
  'sky': 2,
  'dolby': 3,
  'hires': 4,
  'lossless': 5,
  'exhigh': 6,
  'higher': 7,
  'standard': 8,
};

const List<String> _fallbackQualityLevels = <String>[
  'hires',
  'lossless',
  'exhigh',
  'higher',
  'standard',
];

String musicQualityLabel(AppLocalizations l10n, String level) {
  return switch (level) {
    'jymaster' => l10n.musicQualityJymaster,
    'jyeffect' => l10n.musicQualityJyeffect,
    'sky' => l10n.musicQualitySky,
    'dolby' => l10n.musicQualityDolby,
    'hires' => l10n.musicQualityHires,
    'lossless' => l10n.musicQualityLossless,
    'exhigh' => l10n.musicQualityExhigh,
    'higher' => l10n.musicQualityHigher,
    'standard' => l10n.musicQualityStandard,
    _ => level,
  };
}

/// 弹出在线播放音质选择对话框，按已连接平台能力禁用不可用档位。
Future<void> showMusicQualityDialog(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final current =
      ref.read(musicLocalPreferencesControllerProvider).asData?.value ??
      'exhigh';
  final connected =
      ref.read(musicPlatformLibraryProvider).asData?.value.connectedStatuses ??
      const [];
  final available = <String>{
    for (final status in connected) ...status.capabilities.qualityLevels,
  };
  final levels =
      available.isEmpty
            ? List<String>.of(_fallbackQualityLevels)
            : available.toList()
        ..sort(
          (a, b) => (_musicQualityOrder[a] ?? 99).compareTo(
            _musicQualityOrder[b] ?? 99,
          ),
        );
  final selected = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final colors = dialogContext.musicColors;
      return SimpleDialog(
        title: Text(l10n.musicQualityTitle),
        children: [
          RadioGroup<String>(
            groupValue: current,
            onChanged: (value) => Navigator.of(dialogContext).pop(value),
            child: Column(
              children: [
                for (final level in levels)
                  RadioListTile<String>(
                    value: level,
                    title: Text(
                      musicQualityLabel(l10n, level),
                      style: const TextStyle(
                        fontSize: AppTypography.bodyMedium,
                      ),
                    ),
                    activeColor: colors.primary,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    enabled: available.isEmpty || available.contains(level),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
  if (selected == null || selected == current) {
    return;
  }
  await ref
      .read(musicLocalPreferencesControllerProvider.notifier)
      .setOnlineQuality(selected);
}
