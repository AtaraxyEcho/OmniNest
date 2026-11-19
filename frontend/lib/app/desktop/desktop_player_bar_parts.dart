part of 'desktop_player_bar.dart';

/// 空闲态条：样例在没有曲目时仍保留同一块玻璃面板，只是换成引导入口。
class _IdleBar extends StatelessWidget {
  const _IdleBar({required this.onOpenMusic});

  final VoidCallback onOpenMusic;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        const SizedBox(width: 6),
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: skin.raise2,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(DesktopIcons.music, size: 20, color: skin.text3),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.desktopNothingPlaying,
                style: DesktopType.denseStrong(skin.text),
              ),
              Text(
                l10n.desktopNothingPlayingHint,
                style: DesktopType.micro(skin.text3),
              ),
            ],
          ),
        ),
        DesktopButton(
          label: l10n.desktopOpenMusic,
          icon: DesktopIcons.chevron,
          variant: DesktopButtonVariant.soft,
          onPressed: onOpenMusic,
        ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    super.key,
    required this.playing,
    required this.onPressed,
  });

  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final label = playing ? l10n.desktopPause : l10n.desktopPlay;
    return Semantics(
      button: true,
      label: label,
      child: DesktopHover(
        builder:
            (context, hovered) => GestureDetector(
              onTap: onPressed,
              behavior: HitTestBehavior.opaque,
              child: Tooltip(
                message: label,
                child: AnimatedScale(
                  duration: MotionToken.reduced(context, MotionToken.fast),
                  curve: MotionToken.curve,
                  scale: hovered ? 1.1 : 1,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: skin.text,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: skin.accentWash(0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                          spreadRadius: -6,
                        ),
                      ],
                    ),
                    child: Icon(
                      playing ? DesktopIcons.pause : DesktopIcons.play,
                      size: 18,
                      color: skin.bg,
                    ),
                  ),
                ),
              ),
            ),
      ),
    );
  }
}

/// 播放条的时间轴与进度条：自行订阅 16ms 位置流。
///
/// 抽出来是为了把重建范围压到这一行：外层 Row 的封面、控制按钮与频谱
/// 不再随播放位置每帧重建。玻璃面板的 child 保持同一实例，backdrop 层
/// 才不会跟着每帧重录。
class _PlayerSeekBar extends StatelessWidget {
  const _PlayerSeekBar({
    required this.timeline,
    required this.scrubSeconds,
    required this.durationSeconds,
    required this.onScrub,
    required this.onCommit,
  });

  final MusicPortalPlaybackTimeline timeline;
  final double? scrubSeconds;
  final int durationSeconds;
  final ValueChanged<double> onScrub;
  final ValueChanged<double> onCommit;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return SizedBox(
      height: DesktopMetrics.playerBarSeekHeight,
      child: StreamBuilder<Duration>(
        stream: timeline.positionStream,
        initialData: timeline.position,
        builder: (context, snapshot) {
          final positionSeconds =
              scrubSeconds ??
              (snapshot.data ?? Duration.zero).inMilliseconds / 1000;
          return Row(
            children: [
              SizedBox(
                width: DesktopMetrics.playerBarSeekTimeWidth,
                child: Text(
                  formatDesktopClock(
                    Duration(milliseconds: (positionSeconds * 1000).round()),
                  ),
                  textAlign: TextAlign.center,
                  style: DesktopType.numeric(skin.text3).copyWith(height: 1),
                ),
              ),
              SizedBox(width: DesktopMetrics.playerBarSeekGap),
              Expanded(
                child: DesktopSlider(
                  height: DesktopMetrics.playerBarSeekHeight,
                  value: positionSeconds,
                  max: durationSeconds <= 0 ? 1 : durationSeconds.toDouble(),
                  onChanged: durationSeconds <= 0 ? (_) {} : onScrub,
                  onCommit: durationSeconds <= 0 ? null : onCommit,
                ),
              ),
              SizedBox(width: DesktopMetrics.playerBarSeekGap),
              SizedBox(
                width: DesktopMetrics.playerBarSeekTimeWidth,
                child: Text(
                  formatDesktopClock(Duration(seconds: durationSeconds)),
                  textAlign: TextAlign.center,
                  style: DesktopType.numeric(skin.text3).copyWith(height: 1),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
