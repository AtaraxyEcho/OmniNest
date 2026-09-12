import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/music/application/music_local_preferences_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/application/music_sleep_timer_controller.dart';

/// 弹出播放设置对话框：定时关闭档位与播放倍速。
Future<void> showMusicPlaybackSettingsDialog(
  BuildContext context,
  WidgetRef ref,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _MusicPlaybackSettingsDialog(),
  );
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
    final session = ref.watch(musicPlaybackSessionProvider);
    return AlertDialog(
      title: Text(l10n.musicPlaybackSettings),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.musicSleepTimer,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
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
                              .read(musicSleepTimerControllerProvider.notifier)
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
            Text(
              l10n.musicPlaybackSpeed,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
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
                              musicLocalPreferencesControllerProvider.notifier,
                            )
                            .setPlaybackSpeed(preset);
                        setState(() => _speed = preset);
                      },
                    ),
                ],
              ),
            if (session.player.state.speed != _speed) ...[
              const SizedBox(height: 8),
              Text(
                l10n.musicSpeedApplyHint,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: AppTypography.labelSmall,
                ),
              ),
            ],
          ],
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

  String _formatSpeed(double speed) {
    return speed == speed.roundToDouble()
        ? speed.toInt().toString()
        : speed.toStringAsFixed(2);
  }
}
