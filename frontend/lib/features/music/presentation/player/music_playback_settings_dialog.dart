import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/music/application/music_local_preferences_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/application/music_sleep_timer_controller.dart';

/// 弹出播放设置对话框：定时关闭、播放倍速与在线音质。
Future<void> showMusicPlaybackSettingsDialog(
  BuildContext context,
  WidgetRef ref,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _MusicPlaybackSettingsDialog(),
  );
}

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

const List<Duration> _sleepPresets = <Duration>[
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(minutes: 60),
  Duration(minutes: 90),
];

const List<double> _speedPresets = <double>[0.75, 1.0, 1.25, 1.5, 2.0];

class _MusicPlaybackSettingsDialog extends ConsumerStatefulWidget {
  const _MusicPlaybackSettingsDialog();

  @override
  ConsumerState<_MusicPlaybackSettingsDialog> createState() =>
      _MusicPlaybackSettingsDialogState();
}

class _MusicPlaybackSettingsDialogState
    extends ConsumerState<_MusicPlaybackSettingsDialog> {
  double _speed = 1.0;
  bool _speedLoading = true;

  @override
  void initState() {
    super.initState();
    ref
        .read(musicLocalPreferencesControllerProvider.notifier)
        .loadPlaybackSpeed()
        .then((value) {
          if (mounted) {
            setState(() {
              _speed = value;
              _speedLoading = false;
            });
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final timer = ref.watch(musicSleepTimerControllerProvider);
    final currentQuality =
        ref.watch(musicLocalPreferencesControllerProvider).asData?.value ??
        'exhigh';
    final availableQualities = _availableQualities();
    final qualityLevels = _sortedQualityLevels(availableQualities);
    return AlertDialog(
      title: Text(l10n.musicPlaybackSettings),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(context, l10n.musicSleepTimer),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in _sleepPresets)
                    ChoiceChip(
                      label: Text(l10n.musicSleepMinutes(preset.inMinutes)),
                      selected:
                          timer.remaining != null &&
                          timer.remaining!.inMinutes == preset.inMinutes,
                      onSelected:
                          (_) => ref
                              .read(musicSleepTimerControllerProvider.notifier)
                              .start(preset),
                    ),
                  ChoiceChip(
                    label: Text(l10n.musicSleepAfterCurrentTrack),
                    selected: timer.stopAfterCurrentTrack,
                    onSelected:
                        (_) =>
                            ref
                                .read(
                                  musicSleepTimerControllerProvider.notifier,
                                )
                                .toggleStopAfterCurrentTrack(),
                  ),
                  if (timer.active)
                    ChoiceChip(
                      label: Text(l10n.musicSleepOff),
                      selected: false,
                      onSelected:
                          (_) =>
                              ref
                                  .read(
                                    musicSleepTimerControllerProvider.notifier,
                                  )
                                  .cancel(),
                    ),
                ],
              ),
              if (timer.remaining != null) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.musicSleepRemaining(
                    timer.remaining!.inMinutes,
                    timer.remaining!.inSeconds % 60,
                  ),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: AppTypography.bodySmall,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _sectionTitle(context, l10n.musicPlaybackSpeed),
              const SizedBox(height: 8),
              if (_speedLoading)
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in _speedPresets)
                      ChoiceChip(
                        label: Text('x${_formatSpeed(preset)}'),
                        selected: (_speed - preset).abs() < 0.001,
                        onSelected: (_) {
                          ref
                              .read(
                                musicLocalPreferencesControllerProvider
                                    .notifier,
                              )
                              .setPlaybackSpeed(preset);
                          setState(() => _speed = preset);
                        },
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              Text(
                l10n.musicSpeedApplyHint,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: AppTypography.labelSmall,
                ),
              ),
              const SizedBox(height: 20),
              _sectionTitle(context, l10n.musicQualityTitle),
              const SizedBox(height: 4),
              Text(
                l10n.musicQualityHint,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: AppTypography.labelSmall,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final level in qualityLevels)
                    ChoiceChip(
                      label: Text(musicQualityLabel(l10n, level)),
                      selected: level == currentQuality,
                      onSelected:
                          availableQualities.isNotEmpty &&
                                  !availableQualities.contains(level)
                              ? null
                              : (_) => ref
                                  .read(
                                    musicLocalPreferencesControllerProvider
                                        .notifier,
                                  )
                                  .setOnlineQuality(level),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.musicClose),
        ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    );
  }

  /// 已连接平台能力位的并集；为空时回退到全档位（后端有降级探测兜底）。
  Set<String> _availableQualities() {
    final connected =
        ref
            .read(musicPlatformLibraryProvider)
            .asData
            ?.value
            .connectedStatuses ??
        const [];
    return <String>{
      for (final status in connected) ...status.capabilities.qualityLevels,
    };
  }

  List<String> _sortedQualityLevels(Set<String> available) {
    final levels =
        available.isEmpty
            ? List<String>.of(_fallbackQualityLevels)
            : available.toList();
    levels.sort(
      (a, b) =>
          (_musicQualityOrder[a] ?? 99).compareTo(_musicQualityOrder[b] ?? 99),
    );
    return levels;
  }

  String _formatSpeed(double speed) {
    return speed == speed.roundToDouble()
        ? speed.toInt().toString()
        : speed.toStringAsFixed(2);
  }
}
