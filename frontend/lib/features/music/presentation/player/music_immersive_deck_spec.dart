part of 'music_immersive_player.dart';

/// 卡组列底部的「音频参数胶囊」。
class _DigitalDeckSpecCapsule extends StatelessWidget {
  const _DigitalDeckSpecCapsule({
    required this.track,
    required this.scale,
    this.servedQualityLabel,
  });

  final MusicTrack? track;
  final double scale;

  /// 在线曲目播放计划携带的、平台实际签发的音质档位（已本地化）；
  /// 本地曲目的真实采样率/码率经 [MusicTrack.qualityText] 展示。
  final String? servedQualityLabel;

  /// 无损容器集合：用于把格式映射到既有的音质文案。
  static const Set<String> _losslessFormats = <String>{
    'flac',
    'wav',
    'ape',
    'alac',
    'dsf',
    'dff',
    'aiff',
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final format = track?.format.trim() ?? '';
    final normalized = format.toLowerCase();
    // 右侧状态胶囊优先展示平台实际签发的音质档位；本地曲目按容器格式
    // 映射为无损/普通。
    final quality =
        servedQualityLabel ??
        (_losslessFormats.contains(normalized)
            ? l10n.musicQualityLossless
            : l10n.musicQualityStandard);
    // 第二行优先展示真实音频参数（采样率 / 码率，扫描元数据写入），
    // 缺失时回落到容器格式。
    final specText =
        track == null || track!.qualityText.isEmpty ? '' : track!.qualityText;
    final radius = BorderRadius.circular(kMusicDeckSpecRadius * scale);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kMusicDeckCardSurfaceColor.withValues(
          alpha: kMusicDeckSpecBackgroundAlpha,
        ),
        borderRadius: radius,
        border: Border.all(
          color: Colors.white.withValues(alpha: kMusicDeckSpecBorderAlpha),
          width: kMusicDeckCardBorderWidth * scale,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24 * scale,
            offset: Offset(0, 8 * scale),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(kMusicDeckSpecPadding * scale),
        child: Row(
          children: [
            Icon(
              Icons.equalizer_rounded,
              color: Colors.white,
              size: 16 * scale,
            ),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.musicQualityTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // 行高必须与 kMusicDeckSpecHeight 的推导一致并强制 strut，
                    // 否则字体自身行高会把行盒撑高、撑破胶囊。
                    strutStyle: StrutStyle(
                      fontSize: kMusicDeckSpecTitleFontSize * scale,
                      height: 14 / 11,
                      forceStrutHeight: true,
                    ),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: kMusicDeckSpecTitleFontSize * scale,
                      height: 14 / 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.025 * 11 * scale,
                    ),
                  ),
                  if (specText.isNotEmpty)
                    Text(
                      specText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      strutStyle: StrutStyle(
                        fontSize: kMusicDeckSpecTitleFontSize * scale,
                        height: 16 / 11,
                        forceStrutHeight: true,
                      ),
                      style: TextStyle(
                        color: kMusicLyricTranslationColor,
                        fontSize: kMusicDeckSpecTitleFontSize * scale,
                        height: 16 / 11,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: 8 * scale),
            // 右侧状态胶囊：样例 `Bit-Perfect Stream`，圆点 + 等宽大写小字。
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6 * scale,
                  height: 6 * scale,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 6 * scale),
                Text(
                  quality.toUpperCase(),
                  style: TextStyle(
                    color: kMusicLyricTranslationColor,
                    fontSize: kMusicDeckSpecChipFontSize * scale,
                    height: 14 / 11,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.05 * 10 * scale,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
