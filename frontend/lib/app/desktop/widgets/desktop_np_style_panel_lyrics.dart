part of 'desktop_np_style_panel.dart';

extension _NpLyricsTab on _DesktopNpStylePanelState {
  Widget _buildLyricsTab(
    BuildContext context, {
    required AppLocalizations l10n,
    required bool isZh,
    required DesktopNpStyle style,
    required DesktopNpStyleController controller,
  }) {
    final sizeLabels =
        isZh
            ? const <String>['小', '中', '大']
            : const <String>['Small', 'Medium', 'Large'];
    final activeSizeIndex = desktopNpLyricScales
        .indexWhere((s) => (s - style.lyricScale).abs() < 0.01)
        .clamp(0, 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toggleRow(
          label: l10n.desktopNpWordFill,
          value: style.wordFill,
          onChanged:
              (v) => unawaited(controller.apply(style.copyWith(wordFill: v))),
        ),
        const SizedBox(height: 10),
        // 5 联宽矩形颜料预设卡
        Row(
          children: [
            for (var i = 0; i < DesktopNpPaintPreset.all.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i == DesktopNpPaintPreset.all.length - 1 ? 0 : 8,
                  ),
                  child: GestureDetector(
                    onTap: () {
                      final preset = DesktopNpPaintPreset.all[i];
                      unawaited(
                        controller.apply(
                          style.copyWith(
                            fillAuto: false,
                            fillPaint: preset.paint,
                          ),
                        ),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: 26,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            gradient:
                                DesktopNpPaintPreset.all[i].paint
                                    .toLinearGradient(),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DesktopNpPaintPreset.all[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: DesktopType.nano(DesktopNpStylePanel._muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Current line / Other lines 分目标切换
        _DarkSeg(
          labels: <String>[
            isZh ? '当前行' : 'Current line',
            isZh ? '其他行' : 'Other lines',
          ],
          index: _lyricTarget,
          small: true,
          onChanged: _selectLyricTarget,
        ),
        const SizedBox(height: 10),
        if (_lyricTarget == 0) ...[
          _toggleRow(
            label: isZh ? '跟随封面色调' : 'Follow cover colour',
            value: style.fillAuto,
            onChanged:
                (v) => unawaited(controller.apply(style.copyWith(fillAuto: v))),
          ),
          if (!style.fillAuto) ...[
            const SizedBox(height: 8),
            _PaintEditor(
              paint: style.fillPaint,
              onChanged:
                  (paint) => unawaited(
                    controller.apply(style.copyWith(fillPaint: paint)),
                  ),
            ),
          ],
        ] else ...[
          _PaintEditor(
            paint: style.basePaint,
            onChanged:
                (paint) => unawaited(
                  controller.apply(style.copyWith(basePaint: paint)),
                ),
          ),
          const SizedBox(height: 10),
          _sliderRow(
            label: isZh ? '其他行不透明度' : 'Other lines opacity',
            readout: '${style.baseOpacity}%',
            value: style.baseOpacity.toDouble(),
            min: 8,
            max: 100,
            onChanged:
                (v) => unawaited(
                  controller.apply(
                    style.copyWith(baseOpacity: v.round().clamp(8, 100)),
                  ),
                ),
          ),
        ],
        const SizedBox(height: 14),
        _fieldLabel(l10n.desktopNpSize),
        const SizedBox(height: 6),
        _DarkSeg(
          labels: sizeLabels,
          index: activeSizeIndex,
          small: true,
          onChanged:
              (idx) => unawaited(
                controller.apply(
                  style.copyWith(lyricScale: desktopNpLyricScales[idx]),
                ),
              ),
        ),
        const SizedBox(height: 12),
        _toggleRow(
          label: l10n.desktopNpGlow,
          value: style.glow,
          onChanged:
              (v) => unawaited(controller.apply(style.copyWith(glow: v))),
        ),
        const SizedBox(height: 10),
        _sliderRow(
          label: isZh ? '上下边缘渐隐' : 'Top and bottom fade',
          readout: '${style.lyricFade}%',
          value: style.lyricFade.toDouble(),
          max: 40,
          onChanged:
              (v) => unawaited(
                controller.apply(
                  style.copyWith(lyricFade: v.round().clamp(0, 40)),
                ),
              ),
        ),
      ],
    );
  }
}

/// 吸顶真实 3 行衬线歌词动态预览（60ms 循环演示当前 `fillPaint`/`basePaint` 与逐字填充）。
class _LyricLivePreview extends StatefulWidget {
  const _LyricLivePreview({required this.style, required this.hueColor});

  final DesktopNpStyle style;
  final Color hueColor;

  @override
  State<_LyricLivePreview> createState() => _LyricLivePreviewState();
}

class _LyricLivePreviewState extends State<_LyricLivePreview> {
  Timer? _timer;
  final Stopwatch _watch = Stopwatch();
  double _frac = 0.0;

  @override
  void initState() {
    super.initState();
    _watch.start();
    _timer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (!mounted) return;
      final cycle = (_watch.elapsedMilliseconds / 3600.0) % 1.25;
      final next = ((cycle / 1.25) * 1.1).clamp(0.0, 1.0);
      if ((next - _frac).abs() > 0.005) {
        setState(() => _frac = next);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _watch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('zh');
    final lines =
        isZh
            ? const <String>['晨光里的微澜静静散开', '呼吸慢慢沉入温柔的宁静', '再也没有什么需要背负']
            : const <String>[
              'Held in the glow of the morning',
              'Breathing slowly into the quiet',
              'Nothing left to carry',
            ];
    final style = widget.style;
    final fillPaint = style.effectiveFillPaint(widget.hueColor);
    final basePaint = style.basePaint;
    final baseOp = (style.baseOpacity / 100.0).clamp(0.08, 1.0);
    final baseTextStyle = DesktopType.sectionTitle(Colors.white).copyWith(
      fontSize: _npCaptionSize,
      height: 1.35,
      fontWeight: FontWeight.w500,
    );

    Widget paintedLine(String text, {required bool isCurrent}) {
      final baseLayer = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) => basePaint.createShader(rect, opacity: baseOp),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: baseTextStyle,
        ),
      );
      if (!isCurrent) return baseLayer;

      final glowColor = fillPaint.primaryColor.withValues(alpha: 0.55);
      final sungLayer = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) => fillPaint.createShader(rect),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: baseTextStyle.copyWith(
            shadows:
                style.glow
                    ? <Shadow>[Shadow(color: glowColor, blurRadius: 20)]
                    : null,
          ),
        ),
      );

      if (!style.wordFill) {
        return sungLayer;
      }

      final f = _frac.clamp(0.0, 1.0);
      return Stack(
        children: [
          baseLayer,
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) {
              final edge = (f + 0.03).clamp(0.0, 1.0);
              return LinearGradient(
                colors: const <Color>[
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                  Colors.transparent,
                ],
                stops: <double>[0.0, f, edge, 1.0],
              ).createShader(rect);
            },
            child: sungLayer,
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DesktopNpStylePanel._line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          paintedLine(lines[0], isCurrent: false),
          const SizedBox(height: 5),
          paintedLine(lines[1], isCurrent: true),
          const SizedBox(height: 5),
          paintedLine(lines[2], isCurrent: false),
        ],
      ),
    );
  }
}
