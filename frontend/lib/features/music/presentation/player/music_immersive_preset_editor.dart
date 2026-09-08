part of 'music_immersive_player.dart';

class _MusicVisualizerEditor extends StatefulWidget {
  const _MusicVisualizerEditor({
    super.key,
    required this.palette,
    required this.source,
    required this.onChanged,
    required this.onSave,
    required this.onClose,
  });

  final MusicImmersivePalette palette;
  final PortalMusicVisualizerSettings source;
  final ValueChanged<PortalMusicVisualizerSettings> onChanged;
  final ValueChanged<PortalMusicVisualizerSettings> onSave;
  final VoidCallback onClose;

  @override
  State<_MusicVisualizerEditor> createState() => _MusicVisualizerEditorState();
}

class _MusicVisualizerEditorState extends State<_MusicVisualizerEditor> {
  late PortalMusicVisualizerSettings _draft;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _draft = widget.source;
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.82),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 10, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.portalMusicVisualizerEdit,
                        style: TextStyle(
                          color: widget.palette.text,
                          fontSize: AppTypography.titleLarge,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.portalMusicVisualizerResetDefault,
                      onPressed: _resetToDefault,
                      icon: Icon(
                        Icons.restart_alt_rounded,
                        color: widget.palette.text,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip:
                          MaterialLocalizations.of(context).closeButtonTooltip,
                      onPressed: widget.onClose,
                      icon: Icon(
                        Icons.close_rounded,
                        color: widget.palette.text,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    children: [
                      _VisualEditorSection(
                        palette: widget.palette,
                        title: l10n.portalMusicVisualizerOriginalCover,
                        children: [
                          _VisualSwitch(
                            palette: widget.palette,
                            label: l10n.portalMusicVisualizerOriginalCover,
                            value: _draft.coverElements.originalCoverEnabled,
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    coverElements: _draft.coverElements
                                        .copyWith(originalCoverEnabled: value),
                                  ),
                                ),
                          ),
                          _VisualSwitch(
                            palette: widget.palette,
                            label: l10n.portalMusicVisualizerCoverBorder,
                            value: _draft.coverElements.borderEnabled,
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    coverElements: _draft.coverElements
                                        .copyWith(borderEnabled: value),
                                  ),
                                ),
                          ),
                          _VisualSlider(
                            palette: widget.palette,
                            label: l10n.musicVisualizerCoverSize,
                            value: _draft.coverElements.sizeScale,
                            min: 0.7,
                            max: 1.15,
                            divisions: 18,
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    coverElements: _draft.coverElements
                                        .copyWith(sizeScale: value),
                                  ),
                                ),
                          ),
                          _VisualSlider(
                            palette: widget.palette,
                            label: l10n.musicVisualizerCoverRadius,
                            value: _draft.coverElements.cornerRadius,
                            min: 0,
                            max: 16,
                            divisions: 16,
                            displayAsInteger: true,
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    coverElements: _draft.coverElements
                                        .copyWith(cornerRadius: value),
                                  ),
                                ),
                          ),
                          _VisualSlider(
                            palette: widget.palette,
                            label: l10n.musicVisualizerCoverTilt,
                            value: _draft.coverElements.tiltDegrees,
                            min: -12,
                            max: 12,
                            divisions: 24,
                            displayAsInteger: true,
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    coverElements: _draft.coverElements
                                        .copyWith(tiltDegrees: value),
                                  ),
                                ),
                          ),
                          _VisualSlider(
                            palette: widget.palette,
                            label: l10n.musicVisualizerHeroCoverOpacity,
                            value: _draft.coverElements.opacity,
                            min: 0,
                            max: 1,
                            divisions: 20,
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    coverElements: _draft.coverElements
                                        .copyWith(opacity: value),
                                  ),
                                ),
                          ),
                        ],
                      ),
                      _VisualEditorSection(
                        palette: widget.palette,
                        title: l10n.portalMusicVisualizerLyrics,
                        children: [
                          _VisualSwitch(
                            palette: widget.palette,
                            label: l10n.portalMusicVisualizerLyrics,
                            value: _draft.lyrics.enabled,
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    lyrics: _draft.lyrics.copyWith(
                                      enabled: value,
                                    ),
                                  ),
                                ),
                          ),
                          _VisualSlider(
                            palette: widget.palette,
                            label: l10n.portalMusicVisualizerCurrentFont,
                            value: _draft.lyrics.currentFontScale,
                            min: 0.82,
                            max: 1.18,
                            divisions: 18,
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    lyrics: _draft.lyrics.copyWith(
                                      currentFontScale: value,
                                    ),
                                  ),
                                ),
                          ),
                          _VisualSlider(
                            palette: widget.palette,
                            label: l10n.portalMusicVisualizerInactiveOpacity,
                            value: _draft.lyrics.inactiveOpacity,
                            min: 0.25,
                            max: 0.75,
                            divisions: 10,
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    lyrics: _draft.lyrics.copyWith(
                                      inactiveOpacity: value,
                                    ),
                                  ),
                                ),
                          ),
                          _VisualColorField(
                            palette: widget.palette,
                            label: l10n.musicVisualizerLyricActiveColor,
                            value: Color(_draft.lyrics.activeColorValue),
                            onChanged:
                                (color) => _update(
                                  _draft.copyWith(
                                    lyrics: _draft.lyrics.copyWith(
                                      activeColorValue: color.toARGB32(),
                                    ),
                                  ),
                                ),
                          ),
                          _VisualColorField(
                            palette: widget.palette,
                            label: l10n.musicVisualizerLyricReadColor,
                            value: Color(_draft.lyrics.readColorValue),
                            onChanged:
                                (color) => _update(
                                  _draft.copyWith(
                                    lyrics: _draft.lyrics.copyWith(
                                      readColorValue: color.toARGB32(),
                                    ),
                                  ),
                                ),
                          ),
                          _VisualColorField(
                            palette: widget.palette,
                            label: l10n.musicVisualizerLyricUnreadColor,
                            value: Color(_draft.lyrics.unreadColorValue),
                            onChanged:
                                (color) => _update(
                                  _draft.copyWith(
                                    lyrics: _draft.lyrics.copyWith(
                                      unreadColorValue: color.toARGB32(),
                                    ),
                                  ),
                                ),
                          ),
                          _VisualSwitch(
                            palette: widget.palette,
                            label: l10n.musicVisualizerLyricBreathing,
                            value: _draft.lyrics.breathingEnabled,
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    lyrics: _draft.lyrics.copyWith(
                                      breathingEnabled: value,
                                    ),
                                  ),
                                ),
                          ),
                          _VisualSlider(
                            palette: widget.palette,
                            label: l10n.portalMusicVisualizerVisibleLines,
                            value: _draft.lyrics.visibleLines.toDouble(),
                            min: 1,
                            max: 9,
                            divisions: 8,
                            displayAsInteger: true,
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    lyrics: _draft.lyrics.copyWith(
                                      visibleLines: value.round(),
                                    ),
                                  ),
                                ),
                          ),
                          _VisualSlider(
                            palette: widget.palette,
                            label: l10n.musicVisualizerLyricLineSpacing,
                            value: _draft.lyrics.lineSpacing,
                            min: 0.75,
                            max: 1.65,
                            divisions: 18,
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    lyrics: _draft.lyrics.copyWith(
                                      lineSpacing: value,
                                    ),
                                  ),
                                ),
                          ),
                          _VisualDropdown<PortalLyricPosition>(
                            palette: widget.palette,
                            label: l10n.musicVisualizerLyricPosition,
                            value: _draft.lyrics.position,
                            values: PortalLyricPosition.values,
                            labelBuilder:
                                (value) => switch (value) {
                                  PortalLyricPosition.left =>
                                    l10n.musicVisualizerLyricPositionLeft,
                                  PortalLyricPosition.center =>
                                    l10n.musicVisualizerLyricPositionCenter,
                                  PortalLyricPosition.right =>
                                    l10n.musicVisualizerLyricPositionRight,
                                },
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    lyrics: _draft.lyrics.copyWith(
                                      position: value,
                                    ),
                                  ),
                                ),
                          ),
                          _VisualSwitch(
                            palette: widget.palette,
                            label: l10n.portalMusicVisualizerLyricGlow,
                            value: _draft.lyrics.shadowEnabled,
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    lyrics: _draft.lyrics.copyWith(
                                      shadowEnabled: value,
                                    ),
                                  ),
                                ),
                          ),
                          if (_draft.lyrics.shadowEnabled) ...[
                            _VisualSlider(
                              palette: widget.palette,
                              label: l10n.musicVisualizerLyricGlowIntensity,
                              value: _draft.lyrics.glowIntensity,
                              min: 0,
                              max: 2,
                              divisions: 20,
                              onChanged:
                                  (value) => _update(
                                    _draft.copyWith(
                                      lyrics: _draft.lyrics.copyWith(
                                        glowIntensity: value,
                                      ),
                                    ),
                                  ),
                            ),
                            _VisualColorField(
                              palette: widget.palette,
                              label: l10n.musicVisualizerLyricGlowColor,
                              value: Color(_draft.lyrics.glowColorValue),
                              onChanged:
                                  (color) => _update(
                                    _draft.copyWith(
                                      lyrics: _draft.lyrics.copyWith(
                                        glowColorValue: color.toARGB32(),
                                      ),
                                    ),
                                  ),
                            ),
                          ],
                        ],
                      ),
                      _VisualEditorSection(
                        palette: widget.palette,
                        title: l10n.musicVisualizerFrequencyResponse,
                        children: [
                          _VisualSlider(
                            palette: widget.palette,
                            label: l10n.portalMusicVisualizerLow,
                            value: _draft.spectrum.lowResponse,
                            min: 0.2,
                            max: 1.8,
                            divisions: 16,
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    spectrum: _draft.spectrum.copyWith(
                                      lowResponse: value,
                                    ),
                                  ),
                                ),
                          ),
                          _VisualSlider(
                            palette: widget.palette,
                            label: l10n.portalMusicVisualizerMid,
                            value: _draft.spectrum.midResponse,
                            min: 0.2,
                            max: 1.8,
                            divisions: 16,
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    spectrum: _draft.spectrum.copyWith(
                                      midResponse: value,
                                    ),
                                  ),
                                ),
                          ),
                          _VisualSlider(
                            palette: widget.palette,
                            label: l10n.portalMusicVisualizerHigh,
                            value: _draft.spectrum.highResponse,
                            min: 0.2,
                            max: 1.8,
                            divisions: 16,
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    spectrum: _draft.spectrum.copyWith(
                                      highResponse: value,
                                    ),
                                  ),
                                ),
                          ),
                        ],
                      ),
                      _VisualEditorSection(
                        palette: widget.palette,
                        title: l10n.portalMusicVisualizerPlayer,
                        children: [
                          _VisualSwitch(
                            palette: widget.palette,
                            label: l10n.musicVisualizerPlayerVisible,
                            value: _draft.player.enabled,
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    player: _draft.player.copyWith(
                                      enabled: value,
                                    ),
                                  ),
                                ),
                          ),
                          _VisualSwitch(
                            palette: widget.palette,
                            label: l10n.musicVisualizerAudioBar,
                            value: _draft.player.audioBarEnabled,
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    player: _draft.player.copyWith(
                                      audioBarEnabled: value,
                                    ),
                                  ),
                                ),
                          ),
                          if (_draft.player.audioBarEnabled)
                            _VisualDropdown<MusicAudioBarStyle>(
                              palette: widget.palette,
                              label: l10n.musicVisualizerAudioBarStyle,
                              value: _draft.player.audioBarStyle,
                              values: MusicAudioBarStyle.values,
                              labelBuilder:
                                  (value) => switch (value) {
                                    MusicAudioBarStyle.spectrumBars =>
                                      l10n.musicVisualizerAudioBarSpectrum,
                                    MusicAudioBarStyle.lineWave =>
                                      l10n.musicVisualizerAudioBarLine,
                                    MusicAudioBarStyle.pulseDots =>
                                      l10n.musicVisualizerAudioBarDots,
                                  },
                              onChanged:
                                  (value) => _update(
                                    _draft.copyWith(
                                      player: _draft.player.copyWith(
                                        audioBarStyle: value,
                                      ),
                                    ),
                                  ),
                            ),
                          _VisualSwitch(
                            palette: widget.palette,
                            label: l10n.portalMusicVisualizerProgressControl,
                            value: _draft.player.progressEnabled,
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    player: _draft.player.copyWith(
                                      progressEnabled: value,
                                    ),
                                  ),
                                ),
                          ),
                          _VisualSwitch(
                            palette: widget.palette,
                            label: l10n.portalMusicVisualizerVolume,
                            value: _draft.player.volumeEnabled,
                            onChanged:
                                (value) => _update(
                                  _draft.copyWith(
                                    player: _draft.player.copyWith(
                                      volumeEnabled: value,
                                    ),
                                  ),
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: widget.onClose,
                      child: Text(
                        MaterialLocalizations.of(context).cancelButtonLabel,
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: () => widget.onSave(_draft),
                      child: Text(l10n.portalMusicVisualizerSave),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _update(PortalMusicVisualizerSettings next) {
    setState(() => _draft = next);
    widget.onChanged(next);
  }

  void _resetToDefault() {
    _update(PortalMusicVisualizerSettings.defaults);
  }
}

class _VisualEditorSection extends StatelessWidget {
  const _VisualEditorSection({
    required this.palette,
    required this.title,
    required this.children,
  });

  final MusicImmersivePalette palette;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title,
              style: TextStyle(
                color: palette.text.withValues(alpha: 0.82),
                fontSize: AppTypography.bodyLarge,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Material(
            color: Colors.white.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisualSwitch extends StatelessWidget {
  const _VisualSwitch({
    required this.palette,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final MusicImmersivePalette palette;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label, style: TextStyle(color: palette.text)),
      value: value,
      onChanged: onChanged,
      activeTrackColor: palette.accent.withValues(alpha: 0.55),
      activeThumbColor: palette.text,
    );
  }
}

class _VisualDropdown<T> extends StatelessWidget {
  const _VisualDropdown({
    required this.palette,
    required this.label,
    required this.value,
    required this.values,
    required this.labelBuilder,
    required this.onChanged,
  });

  final MusicImmersivePalette palette;
  final String label;
  final T value;
  final List<T> values;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      dropdownColor: const Color(0xFF141D23),
      style: TextStyle(color: palette.text),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: palette.text.withValues(alpha: 0.68)),
      ),
      items: values
          .map(
            (item) => DropdownMenuItem<T>(
              value: item,
              child: Text(labelBuilder(item)),
            ),
          )
          .toList(growable: false),
      onChanged: (next) {
        if (next != null) {
          onChanged(next);
        }
      },
    );
  }
}

class _VisualSlider extends StatelessWidget {
  const _VisualSlider({
    required this.palette,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.displayAsInteger = false,
  });

  final MusicImmersivePalette palette;
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final bool displayAsInteger;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final display =
        displayAsInteger ? value.round().toString() : value.toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: TextStyle(color: palette.text)),
              ),
              Text(
                display,
                style: TextStyle(
                  color: palette.text.withValues(alpha: 0.62),
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          AppSlider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            semanticLabel: label,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
