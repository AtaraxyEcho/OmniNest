part of 'desktop_np_style_panel.dart';

extension _NpBackgroundTab on _DesktopNpStylePanelState {
  Widget _buildBackgroundTab(
    BuildContext context, {
    required AppLocalizations l10n,
    required bool isZh,
    required Color hue,
    required DesktopNpStyle style,
    required DesktopNpStyleController controller,
  }) {
    final isDynamic =
        style.background == DesktopNpBackground.aurora ||
        style.background == DesktopNpBackground.spectrum ||
        style.background == DesktopNpBackground.library;
    final note = switch (style.background) {
      DesktopNpBackground.library =>
        isZh
            ? '使用壁纸库中的壁纸，视频、动图与极光将保持动态流动，不会修改全局桌面壁纸。'
            : 'Uses a wallpaper from your library. Videos, GIFs and live aurora keep moving without changing your desktop wallpaper.',
      _ when isDynamic =>
        isZh
            ? '动态壁纸已开启：色彩会随音乐流动并跟随播放状态。'
            : 'Dynamic wallpaper is on: colours flow with the music and follow the playing state.',
      _ =>
        isZh
            ? '静态背景。选择极光或频谱脉动可启用动态壁纸。'
            : 'Static background. Pick Aurora or Spectrum pulse for a dynamic wallpaper.',
    };

    final bgEntries = <MapEntry<DesktopNpBackground, String>>[
      MapEntry(DesktopNpBackground.aurora, l10n.desktopNpAurora),
      MapEntry(DesktopNpBackground.spectrum, l10n.desktopNpSpectrum),
      MapEntry(DesktopNpBackground.library, l10n.desktopNpLibrary),
      MapEntry(DesktopNpBackground.cover, l10n.desktopNpCover),
      MapEntry(DesktopNpBackground.gradient, l10n.desktopNpGradient),
      MapEntry(DesktopNpBackground.plain, l10n.desktopNpPlain),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 6 联风格预设
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < DesktopNpPreset.all.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i == DesktopNpPreset.all.length - 1 ? 0 : 8,
                  ),
                  child: GestureDetector(
                    onTap: () {
                      final preset = DesktopNpPreset.all[i];
                      unawaited(controller.apply(preset.applyTo(style)));
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AspectRatio(
                          aspectRatio: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  i == 0 ? hue : DesktopNpPreset.all[i].top,
                                  DesktopNpPreset.all[i].bottom,
                                ],
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _presetLabel(l10n, i),
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
        const SizedBox(height: 20),
        _sectionHeading(l10n.desktopNpBackground),
        const SizedBox(height: 8),
        // 3×2 等宽网格
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 6),
          Row(
            children: [
              for (var col = 0; col < 3; col++) ...[
                if (col > 0) const SizedBox(width: 6),
                Expanded(
                  child: _GridChoiceButton(
                    label: bgEntries[row * 3 + col].value,
                    selected: style.background == bgEntries[row * 3 + col].key,
                    onTap:
                        () => unawaited(
                          controller.apply(
                            style.copyWith(
                              background: bgEntries[row * 3 + col].key,
                            ),
                          ),
                        ),
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(
          note,
          style: DesktopType.nano(
            Colors.white.withValues(alpha: 0.50),
          ).copyWith(height: 1.5),
        ),
        if (style.background == DesktopNpBackground.library) ...[
          const SizedBox(height: 12),
          _WallPicker(
            style: style,
            onSelect: (id) {
              // 严格只更新播放页的 `style.wallId`，不污染全局桌面壁纸。
              unawaited(controller.apply(style.copyWith(wallId: id)));
            },
          ),
        ],
        if (style.background == DesktopNpBackground.gradient) ...[
          const SizedBox(height: 14),
          _toggleRow(
            label: isZh ? '跟随封面色调' : 'Follow cover colour',
            value: style.gradAuto,
            onChanged:
                (v) => unawaited(controller.apply(style.copyWith(gradAuto: v))),
          ),
          if (!style.gradAuto) ...[
            const SizedBox(height: 8),
            _fieldLabel(isZh ? '起始色' : 'Top colour'),
            const SizedBox(height: 6),
            DesktopColorField(
              label: isZh ? '起始色' : 'Top colour',
              value: style.gradStart,
              swatches: const <Color>[
                Color(0xFFFF7E5F),
                Color(0xFF2193B0),
                Color(0xFF4F9D3A),
                Color(0xFFE0568A),
                Color(0xFF6F9A93),
                Color(0xFF3C4147),
              ],
              onChanged:
                  (c) =>
                      unawaited(controller.apply(style.copyWith(gradStart: c))),
            ),
            const SizedBox(height: 10),
            _fieldLabel(isZh ? '结束色' : 'Bottom colour'),
            const SizedBox(height: 6),
            DesktopColorField(
              label: isZh ? '结束色' : 'Bottom colour',
              value: style.gradEnd,
              swatches: const <Color>[
                Color(0xFF3A1C71),
                Color(0xFF0B132B),
                Color(0xFF0A1A10),
                Color(0xFF240D2E),
                Color(0xFF0B1014),
                Color(0xFF080909),
              ],
              onChanged:
                  (c) =>
                      unawaited(controller.apply(style.copyWith(gradEnd: c))),
            ),
          ],
          const SizedBox(height: 10),
          _sliderRow(
            label: isZh ? '渐变方向' : 'Direction',
            readout: '${style.gradAngle.round()}°',
            value: style.gradAngle,
            max: 360,
            onChanged:
                (v) => unawaited(
                  controller.apply(
                    style.copyWith(gradAngle: v.roundToDouble()),
                  ),
                ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _GridChoiceButton(
                  label: isZh ? '从上到下' : 'Top to bottom',
                  selected: style.gradAngle.round() == 180,
                  height: 30,
                  onTap:
                      () => unawaited(
                        controller.apply(style.copyWith(gradAngle: 180)),
                      ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _GridChoiceButton(
                  label: isZh ? '从下到上' : 'Bottom to top',
                  selected: style.gradAngle.round() == 0,
                  height: 30,
                  onTap:
                      () => unawaited(
                        controller.apply(style.copyWith(gradAngle: 0)),
                      ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _GridChoiceButton(
                  label: isZh ? '对角渐变' : 'Diagonal',
                  selected: style.gradAngle.round() == 135,
                  height: 30,
                  onTap:
                      () => unawaited(
                        controller.apply(style.copyWith(gradAngle: 135)),
                      ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 22),
        _sectionHeading(l10n.desktopNpMask),
        const SizedBox(height: 8),
        _sliderRow(
          label: l10n.desktopNpDarkness,
          readout: '${style.mask.round()}%',
          value: style.mask,
          max: 80,
          onChanged:
              (v) => unawaited(
                controller.apply(style.copyWith(mask: v.roundToDouble())),
              ),
        ),
        const SizedBox(height: 8),
        _sliderRow(
          label: l10n.desktopNpBlur,
          readout: '${style.blur.round()}px',
          value: style.blur,
          max: 40,
          onChanged:
              (v) => unawaited(
                controller.apply(style.copyWith(blur: v.roundToDouble())),
              ),
        ),
      ],
    );
  }
}
