import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/features/music/application/music_local_preferences_controller.dart';
import 'package:omninest/features/music/application/music_sleep_timer_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';

/// 弹出播放设置底部抽屉：定时关闭、播放倍速与在线音质。
Future<void> showMusicPlaybackSettingsDialog(
  BuildContext context,
  WidgetRef ref,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const MusicPlaybackSettingsSheet(),
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

class MusicPlaybackSettingsSheet extends ConsumerStatefulWidget {
  const MusicPlaybackSettingsSheet({super.key});

  @override
  ConsumerState<MusicPlaybackSettingsSheet> createState() =>
      _MusicPlaybackSettingsSheetState();
}

class _MusicPlaybackSettingsSheetState
    extends ConsumerState<MusicPlaybackSettingsSheet> {
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
    return FractionallySizedBox(
      heightFactor: 0.62,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: MusicDeckGlass(
            opacity: 0.42,
            blur: 20,
            borderRadius: 14,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 2),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.musicColors.onSurfaceVariant.withValues(
                        alpha: 0.35,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.musicPlaybackSettings,
                          style: TextStyle(
                            color: context.musicColors.onSurface,
                            fontSize: AppTypography.titleMedium,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.musicClose,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, size: 19),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Divider(color: context.musicColors.outline, height: 1),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SettingsSection(
                          icon: Icons.nightlight_round,
                          title: l10n.musicSleepTimer,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final preset in _sleepPresets)
                                    _SettingsChip(
                                      label: l10n.musicSleepMinutes(
                                        preset.inMinutes,
                                      ),
                                      selected:
                                          timer.remaining != null &&
                                          timer.remaining!.inMinutes ==
                                              preset.inMinutes,
                                      onTap:
                                          () => ref
                                              .read(
                                                musicSleepTimerControllerProvider
                                                    .notifier,
                                              )
                                              .start(preset),
                                    ),
                                  _SettingsChip(
                                    label: l10n.musicSleepAfterCurrentTrack,
                                    selected: timer.stopAfterCurrentTrack,
                                    onTap:
                                        () =>
                                            ref
                                                .read(
                                                  musicSleepTimerControllerProvider
                                                      .notifier,
                                                )
                                                .toggleStopAfterCurrentTrack(),
                                  ),
                                ],
                              ),
                              if (timer.remaining != null) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.timer_rounded,
                                      size: 15,
                                      color:
                                          context.musicColors.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      l10n.musicSleepRemaining(
                                        timer.remaining!.inMinutes,
                                        timer.remaining!.inSeconds % 60,
                                      ),
                                      style: TextStyle(
                                        color:
                                            context
                                                .musicColors
                                                .onSurfaceVariant,
                                        fontSize: AppTypography.bodySmall,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      onPressed:
                                          () =>
                                              ref
                                                  .read(
                                                    musicSleepTimerControllerProvider
                                                        .notifier,
                                                  )
                                                  .cancel(),
                                      child: Text(l10n.musicSleepOff),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _SettingsSection(
                          icon: Icons.speed_rounded,
                          title: l10n.musicPlaybackSpeed,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_speedLoading)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                  child: SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final preset in _speedPresets)
                                      _SettingsChip(
                                        label: 'x${_formatSpeed(preset)}',
                                        selected:
                                            (_speed - preset).abs() < 0.001,
                                        onTap: () {
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
                              const SizedBox(height: 10),
                              Text(
                                l10n.musicSpeedApplyHint,
                                style: TextStyle(
                                  color: context.musicColors.onSurfaceVariant,
                                  fontSize: AppTypography.labelSmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _SettingsSection(
                          icon: Icons.high_quality_rounded,
                          title: l10n.musicQualityTitle,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.musicQualityHint,
                                style: TextStyle(
                                  color: context.musicColors.onSurfaceVariant,
                                  fontSize: AppTypography.labelSmall,
                                ),
                              ),
                              const SizedBox(height: 6),
                              for (final level in qualityLevels)
                                _QualityRow(
                                  label: musicQualityLabel(l10n, level),
                                  level: level,
                                  selected: level == currentQuality,
                                  enabled:
                                      availableQualities.isEmpty ||
                                      availableQualities.contains(level),
                                  onSelected:
                                      () => ref
                                          .read(
                                            musicLocalPreferencesControllerProvider
                                                .notifier,
                                          )
                                          .setOnlineQuality(level),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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

/// 设置分区：带图标的标题与内容。
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: context.musicColors.primary),
            const SizedBox(width: 7),
            Text(
              title,
              style: TextStyle(
                color: context.musicColors.onSurface,
                fontSize: AppTypography.bodyMedium,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

/// 设置选项圆角标签，替代默认 ChoiceChip 的密集描边风格。
class _SettingsChip extends StatelessWidget {
  const _SettingsChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color:
              selected
                  ? colors.primary.withValues(alpha: 0.18)
                  : colors.surfaceContainerHigh.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color:
                selected
                    ? colors.primary.withValues(alpha: 0.65)
                    : colors.outline.withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? colors.primary : colors.onSurface,
            fontSize: AppTypography.bodySmall,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// 音质档位行：左侧档位名与原始等级徽标，右侧选中圆点。
class _QualityRow extends StatelessWidget {
  const _QualityRow({
    required this.label,
    required this.level,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final String label;
  final String level;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.musicColors;
    final l10n = AppLocalizations.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: enabled ? onSelected : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color:
                          enabled
                              ? colors.onSurface
                              : colors.onSurfaceVariant.withValues(alpha: 0.55),
                      fontSize: AppTypography.bodyMedium,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!enabled)
                    Text(
                      l10n.musicQualityUnsupported,
                      style: TextStyle(
                        color: colors.onSurfaceVariant.withValues(alpha: 0.55),
                        fontSize: AppTypography.labelSmall,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              level,
              style: TextStyle(
                color: colors.onSurfaceVariant.withValues(alpha: 0.6),
                fontSize: AppTypography.labelSmall,
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 19,
              color: selected ? colors.primary : colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
