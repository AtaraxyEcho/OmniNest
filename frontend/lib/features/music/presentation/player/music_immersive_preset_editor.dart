import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/widgets/app_dropdown.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/features/music/domain/music_visualizer_preset.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_style.dart';
import 'package:omninest/features/music/presentation/player/music_visual_color_picker.dart';

/// 编辑视觉面板的分区：桌面沉浸与移动端歌词样式各一组。
///
/// 分区按"参数真实作用于哪个端"划分：桌面组只含桌面沉浸播放页消费的
/// 参数，移动端组只含移动端播放页消费的通用歌词参数；宿主按需注入，
/// 面板上不允许出现当前端调了没有反应的控件。
enum MusicVisualEditorSection { desktop, mobileLyrics }

/// 编辑视觉窗口的面板：桌面沉浸与移动端歌词样式两个分区。
///
/// 独立成库（文件名沿用历史命名）以便直接做 Widget 测试：面板只依赖
/// 传入的视觉设置与回调，不依赖沉浸舞台的 Provider 与路由状态。
/// 改动即时经 [onChanged] 预览，[onSave] 落库，[onClose] 放弃预览。
class MusicVisualEditorPanel extends StatefulWidget {
  const MusicVisualEditorPanel({
    super.key,
    required this.palette,
    required this.source,
    required this.onChanged,
    required this.onSave,
    required this.onClose,
    this.lyricScrollMode = true,
    this.onLyricScrollModeChanged,
    this.sections = const <MusicVisualEditorSection>{
      MusicVisualEditorSection.desktop,
      MusicVisualEditorSection.mobileLyrics,
    },
  });

  final MusicImmersivePalette palette;
  final PortalMusicVisualizerSettings source;

  /// 歌词区域形态（设备级偏好，写回本机存储而非跨端视觉设置）：
  /// true 为滚动歌词，false 为多行歌词。
  final bool lyricScrollMode;
  final ValueChanged<bool>? onLyricScrollModeChanged;
  final ValueChanged<PortalMusicVisualizerSettings> onChanged;
  final ValueChanged<PortalMusicVisualizerSettings> onSave;
  final VoidCallback onClose;

  /// 展示哪些分区（桌面沉浸页传 desktop，移动端播放页传 mobileLyrics）。
  final Set<MusicVisualEditorSection> sections;

  @override
  State<MusicVisualEditorPanel> createState() => _MusicVisualEditorPanelState();
}

class _MusicVisualEditorPanelState extends State<MusicVisualEditorPanel> {
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

  /// 面板 UI 配色：外层已固定注入深色 Theme，此处从深色上下文派生，
  /// 不沿用沉浸播放的固定深色调色板。
  MusicImmersivePalette _editorPalette(BuildContext context) {
    return MusicImmersivePalette.fromColorScheme(Theme.of(context).colorScheme);
  }

  /// 歌词区域形态：宿主传入的设备级偏好映射为两种形态之一。
  PortalLyricLayoutMode get _layoutMode =>
      widget.lyricScrollMode
          ? PortalLyricLayoutMode.scroll
          : PortalLyricLayoutMode.multiline;

  @override
  Widget build(BuildContext context) {
    // 面板统一复用深色主题样式：黑玻璃底色与内嵌表单件（开关、滑条、
    // 下拉、按钮）都在深色 Theme 下渲染，浅色主题不再保留实底分支，
    // 与深色主题观感完全一致。
    return Theme(
      data: musicVisualEditorDarkTheme,
      child: Builder(builder: _buildPanel),
    );
  }

  Widget _buildPanel(BuildContext context) {
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
                          color: _editorPalette(context).text,
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
                        color: _editorPalette(context).text,
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
                        color: _editorPalette(context).text,
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
                      if (widget.sections.contains(
                        MusicVisualEditorSection.desktop,
                      ))
                        _VisualEditorSection(
                          palette: _editorPalette(context),
                          title: l10n.musicVisualizerGroupDesktop,
                          children: [
                            _VisualSwitch(
                              palette: _editorPalette(context),
                              label: l10n.portalMusicVisualizerLyrics,
                              value: _draft.lyrics.enabled,
                              scopeLabel: l10n.musicVisualizerScopeAll,
                              onChanged:
                                  (value) => _update(
                                    _draft.copyWith(
                                      lyrics: _draft.lyrics.copyWith(
                                        enabled: value,
                                      ),
                                    ),
                                  ),
                            ),
                            if (_draft.lyrics.enabled) ...[
                              // 桌面布局三预设（居左/居中/居右）：默认居左。
                              // 布局决定主视觉卡组与歌词列的构图，两端共享。
                              _VisualControlGap(
                                scopeLabel: l10n.musicVisualizerScopeDesktop,
                                child: AppDropdown<PortalMusicLayout>(
                                  label: l10n.musicVisualizerLayout,
                                  value: _draft.lyrics.layout,
                                  items: [
                                    for (final entry
                                        in PortalMusicLayout.values)
                                      AppDropdownItem(
                                        value: entry,
                                        label: switch (entry) {
                                          PortalMusicLayout.left =>
                                            l10n.musicVisualizerLayoutLeft,
                                          PortalMusicLayout.center =>
                                            l10n.musicVisualizerLayoutCenter,
                                          PortalMusicLayout.right =>
                                            l10n.musicVisualizerLayoutRight,
                                        },
                                      ),
                                  ],
                                  onChanged:
                                      (value) => _update(
                                        _draft.copyWith(
                                          lyrics: _draft.lyrics.copyWith(
                                            layout:
                                                value ?? _draft.lyrics.layout,
                                          ),
                                        ),
                                      ),
                                ),
                              ),
                              // 居中布局即多行歌词固定窗口、两侧为滚动歌词，
                              // 形态由布局唯一决定，不再单独暴露形态下拉。
                              // 译文行开关：两种形态共用，关闭后译文行不渲染。
                              _VisualSwitch(
                                palette: _editorPalette(context),
                                label: l10n.musicVisualizerLyricTranslation,
                                value: _draft.lyrics.translationEnabled,
                                scopeLabel: l10n.musicVisualizerScopeAll,
                                onChanged:
                                    (value) => _update(
                                      _draft.copyWith(
                                        lyrics: _draft.lyrics.copyWith(
                                          translationEnabled: value,
                                        ),
                                      ),
                                    ),
                              ),
                              // 逐字填充仅在两侧布局的滚动歌词生效；桌面
                              // 居中布局是固定四行窗口，无逐字位，开关随组合隐藏。
                              if (widget.lyricScrollMode &&
                                  _draft.lyrics.layout !=
                                      PortalMusicLayout.center)
                                _VisualSwitch(
                                  palette: _editorPalette(context),
                                  label: l10n.musicVisualizerLyricKaraokeFill,
                                  value: _draft.lyrics.wordFillEnabled,
                                  scopeLabel: l10n.musicVisualizerScopeAll,
                                  onChanged:
                                      (value) => _update(
                                        _draft.copyWith(
                                          lyrics: _draft.lyrics.copyWith(
                                            wordFillEnabled: value,
                                          ),
                                        ),
                                      ),
                                ),
                              // 歌词颜色在桌面复刻形态同样生效：改色后覆盖
                              // 样例常量，恢复默认（纯白）回落样例色。
                              MusicVisualPaintField(
                                palette: _editorPalette(context),
                                label: l10n.musicVisualizerLyricCurrentColor,
                                value: _draft.lyrics.currentPaint,
                                defaultValue:
                                    PortalLyricVisualSettings
                                        .defaults
                                        .currentPaint,
                                scopeLabel: l10n.musicVisualizerScopeAll,
                                onChanged:
                                    (paint) => _update(
                                      _draft.copyWith(
                                        lyrics: _draft.lyrics.copyWith(
                                          currentPaint: paint,
                                        ),
                                      ),
                                    ),
                              ),
                              MusicVisualPaintField(
                                palette: _editorPalette(context),
                                label: l10n.musicVisualizerLyricInactiveColor,
                                value: _draft.lyrics.inactivePaint,
                                defaultValue:
                                    PortalLyricVisualSettings
                                        .defaults
                                        .inactivePaint,
                                scopeLabel: l10n.musicVisualizerScopeAll,
                                onChanged:
                                    (paint) => _update(
                                      _draft.copyWith(
                                        lyrics: _draft.lyrics.copyWith(
                                          inactivePaint: paint,
                                        ),
                                      ),
                                    ),
                              ),
                              _VisualSlider(
                                palette: _editorPalette(context),
                                label: l10n.musicVisualizerLyricOffset,
                                value: _draft.lyrics.offsetMs.toDouble(),
                                min: -500,
                                max: 500,
                                divisions: 20,
                                displayAsInteger: true,
                                valueSigned: true,
                                valueSuffix: ' ms',
                                scopeLabel: l10n.musicVisualizerScopeAll,
                                onChanged:
                                    (value) => _update(
                                      _draft.copyWith(
                                        lyrics: _draft.lyrics.copyWith(
                                          offsetMs: value.round(),
                                        ),
                                      ),
                                    ),
                              ),
                            ],
                            // 堆叠卡片开关：与歌词相互独立，控制封面卡组
                            // 及其下方音频参数胶囊的显隐。
                            _VisualSwitch(
                              palette: _editorPalette(context),
                              label: l10n.musicVisualizerDeckToggle,
                              value: _draft.deckEnabled,
                              scopeLabel: l10n.musicVisualizerScopeDesktop,
                              onChanged:
                                  (value) => _update(
                                    _draft.copyWith(deckEnabled: value),
                                  ),
                            ),
                            // 播放器显隐与歌词开关相互独立，不嵌进歌词启用块。
                            _VisualSwitch(
                              palette: _editorPalette(context),
                              label: l10n.musicVisualizerPlayerVisible,
                              value: _draft.player.enabled,
                              scopeLabel: l10n.musicVisualizerScopeDesktop,
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
                              palette: _editorPalette(context),
                              label: l10n.portalMusicVisualizerProgressControl,
                              value: _draft.player.progressEnabled,
                              scopeLabel: l10n.musicVisualizerScopeDesktop,
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
                              palette: _editorPalette(context),
                              label: l10n.portalMusicVisualizerVolume,
                              value: _draft.player.volumeEnabled,
                              scopeLabel: l10n.musicVisualizerScopeDesktop,
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
                      if (widget.sections.contains(
                        MusicVisualEditorSection.mobileLyrics,
                      ))
                        _VisualEditorSection(
                          palette: _editorPalette(context),
                          title: l10n.musicVisualizerGroupMobileLyrics,
                          children: [
                            // 歌词开关与形态下拉是两端共用设置：桌面组存在时
                            // 由桌面组承载，避免同一控件在面板上出现两次。
                            if (!widget.sections.contains(
                              MusicVisualEditorSection.desktop,
                            )) ...[
                              _VisualSwitch(
                                palette: _editorPalette(context),
                                label: l10n.portalMusicVisualizerLyrics,
                                value: _draft.lyrics.enabled,
                                scopeLabel: l10n.musicVisualizerScopeAll,
                                onChanged:
                                    (value) => _update(
                                      _draft.copyWith(
                                        lyrics: _draft.lyrics.copyWith(
                                          enabled: value,
                                        ),
                                      ),
                                    ),
                              ),
                              _VisualControlGap(
                                scopeLabel: l10n.musicVisualizerScopeAll,
                                child: AppDropdown<PortalLyricLayoutMode>(
                                  label: l10n.musicVisualizerLyricMode,
                                  value: _layoutMode,
                                  items: [
                                    AppDropdownItem(
                                      value: PortalLyricLayoutMode.scroll,
                                      label:
                                          l10n.musicVisualizerLyricModeScroll,
                                    ),
                                    AppDropdownItem(
                                      value: PortalLyricLayoutMode.multiline,
                                      label:
                                          l10n.musicVisualizerLyricModeMultiline,
                                    ),
                                  ],
                                  onChanged:
                                      (value) =>
                                          widget.onLyricScrollModeChanged?.call(
                                            (value ?? _layoutMode) ==
                                                PortalLyricLayoutMode.scroll,
                                          ),
                                ),
                              ),
                            ],
                            if (_draft.lyrics.enabled) ...[
                              // 字号以 px 表达（主流方案）：12–32px 整段歌词共用。
                              _VisualSlider(
                                palette: _editorPalette(context),
                                label: l10n.musicVisualizerLyricFontSize,
                                value: _draft.lyrics.fontSizePx.toDouble(),
                                min: 12,
                                max: 32,
                                divisions: 20,
                                displayAsInteger: true,
                                valueSuffix: ' px',
                                scopeLabel: l10n.musicVisualizerScopeMobile,
                                onChanged:
                                    (value) => _update(
                                      _draft.copyWith(
                                        lyrics: _draft.lyrics.copyWith(
                                          fontSizePx: value.round(),
                                        ),
                                      ),
                                    ),
                              ),
                              if (widget.lyricScrollMode) ...[
                                // 逐字填充仅在滚动形态生效（移动端入口；
                                // 桌面组存在时由桌面组承载，避免重复控件）。
                                if (!widget.sections.contains(
                                  MusicVisualEditorSection.desktop,
                                ))
                                  _VisualSwitch(
                                    palette: _editorPalette(context),
                                    label: l10n.musicVisualizerLyricKaraokeFill,
                                    value: _draft.lyrics.wordFillEnabled,
                                    scopeLabel: l10n.musicVisualizerScopeMobile,
                                    onChanged:
                                        (value) => _update(
                                          _draft.copyWith(
                                            lyrics: _draft.lyrics.copyWith(
                                              wordFillEnabled: value,
                                            ),
                                          ),
                                        ),
                                  ),
                                _VisualSlider(
                                  palette: _editorPalette(context),
                                  label: l10n.musicVisualizerLyricFocusAnchor,
                                  value: _draft.lyrics.focusAnchor,
                                  min: 0.35,
                                  max: 0.65,
                                  divisions: 12,
                                  valuePercent: true,
                                  displayAsInteger: true,
                                  scopeLabel: l10n.musicVisualizerScopeMobile,
                                  onChanged:
                                      (value) => _update(
                                        _draft.copyWith(
                                          lyrics: _draft.lyrics.copyWith(
                                            focusAnchor: value,
                                          ),
                                        ),
                                      ),
                                ),
                                _VisualSwitch(
                                  palette: _editorPalette(context),
                                  label: l10n.musicVisualizerLyricFocusBand,
                                  value: _draft.lyrics.focusBandEnabled,
                                  scopeLabel: l10n.musicVisualizerScopeMobile,
                                  onChanged:
                                      (value) => _update(
                                        _draft.copyWith(
                                          lyrics: _draft.lyrics.copyWith(
                                            focusBandEnabled: value,
                                          ),
                                        ),
                                      ),
                                ),
                                _buildLineSpacingSlider(
                                  context,
                                  l10n,
                                  scopeLabel: l10n.musicVisualizerScopeMobile,
                                ),
                              ],
                              // 多行歌词专属：可见行数 → 行距 → 在读行放大 →
                              // 在读行呼吸（滚动歌词的在读行不放大，靠逐字填充表达）。
                              if (!widget.lyricScrollMode) ...[
                                _VisualSlider(
                                  palette: _editorPalette(context),
                                  label: l10n.portalMusicVisualizerVisibleLines,
                                  value: _draft.lyrics.visibleLines.toDouble(),
                                  min: 1,
                                  max: 9,
                                  divisions: 8,
                                  displayAsInteger: true,
                                  valueSuffix: l10n.musicVisualizerUnitLines,
                                  scopeLabel: l10n.musicVisualizerScopeMobile,
                                  onChanged:
                                      (value) => _update(
                                        _draft.copyWith(
                                          lyrics: _draft.lyrics.copyWith(
                                            visibleLines: value.round(),
                                          ),
                                        ),
                                      ),
                                ),
                                _buildLineSpacingSlider(
                                  context,
                                  l10n,
                                  scopeLabel: l10n.musicVisualizerScopeMobile,
                                ),
                                // 在读行字号（px）：多行形态可大于整段字号。
                                _VisualSlider(
                                  palette: _editorPalette(context),
                                  label: l10n.portalMusicVisualizerCurrentFont,
                                  value:
                                      _draft.lyrics.currentFontSizePx
                                          .toDouble(),
                                  min: 16,
                                  max: 48,
                                  divisions: 32,
                                  displayAsInteger: true,
                                  valueSuffix: ' px',
                                  scopeLabel: l10n.musicVisualizerScopeMobile,
                                  onChanged:
                                      (value) => _update(
                                        _draft.copyWith(
                                          lyrics: _draft.lyrics.copyWith(
                                            currentFontSizePx: value.round(),
                                          ),
                                        ),
                                      ),
                                ),
                                _VisualSwitch(
                                  palette: _editorPalette(context),
                                  label: l10n.musicVisualizerLyricBreathing,
                                  value: _draft.lyrics.breathingEnabled,
                                  scopeLabel: l10n.musicVisualizerScopeMobile,
                                  onChanged:
                                      (value) => _update(
                                        _draft.copyWith(
                                          lyrics: _draft.lyrics.copyWith(
                                            breathingEnabled: value,
                                          ),
                                        ),
                                      ),
                                ),
                              ],
                              _VisualSlider(
                                palette: _editorPalette(context),
                                label:
                                    l10n.portalMusicVisualizerInactiveOpacity,
                                value: _draft.lyrics.inactiveOpacity,
                                min: 0.25,
                                max: 0.75,
                                divisions: 10,
                                valuePercent: true,
                                displayAsInteger: true,
                                scopeLabel: l10n.musicVisualizerScopeMobile,
                                onChanged:
                                    (value) => _update(
                                      _draft.copyWith(
                                        lyrics: _draft.lyrics.copyWith(
                                          inactiveOpacity: value,
                                        ),
                                      ),
                                    ),
                              ),
                            ],
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

  /// 歌词行距滑杆：两种形态都可用，因此按形态分别插在各自动参数块内
  ///（多行歌词要求它紧跟在"可见行数"下方）。
  Widget _buildLineSpacingSlider(
    BuildContext context,
    AppLocalizations l10n, {
    String? scopeLabel,
  }) {
    return _VisualSlider(
      palette: _editorPalette(context),
      label: l10n.musicVisualizerLyricLineSpacing,
      value: _draft.lyrics.lineSpacing,
      min: 0.75,
      max: 1.65,
      divisions: 18,
      valueSuffix: '×',
      scopeLabel: scopeLabel,
      onChanged:
          (value) => _update(
            _draft.copyWith(lyrics: _draft.lyrics.copyWith(lineSpacing: value)),
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
    this.scopeLabel,
  });

  final MusicImmersivePalette palette;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// 生效范围徽标文案（桌面/移动端/通用），为空时不渲染徽标。
  final String? scopeLabel;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: palette.text))),
          if (scopeLabel != null)
            MusicVisualScopeBadge(palette: palette, label: scopeLabel!),
        ],
      ),
      value: value,
      onChanged: onChanged,
      activeTrackColor: palette.accent.withValues(alpha: 0.55),
      activeThumbColor: palette.text,
    );
  }
}

/// 下拉控件之间的统一间距：与滑杆的纵向留白对齐。
class _VisualControlGap extends StatelessWidget {
  const _VisualControlGap({required this.child, this.scopeLabel});

  final Widget child;

  /// 生效范围徽标文案：渲染在控件上缘右侧，与下拉自带的标签同行对齐。
  final String? scopeLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (scopeLabel != null)
            Align(
              alignment: Alignment.centerRight,
              child: MusicVisualScopeBadge(
                palette: MusicImmersivePalette.fromColorScheme(
                  Theme.of(context).colorScheme,
                ),
                label: scopeLabel!,
              ),
            ),
          child,
        ],
      ),
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
    this.valueSuffix = '',
    this.valuePercent = false,
    this.valueSigned = false,
    this.scopeLabel,
  });

  final MusicImmersivePalette palette;
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final bool displayAsInteger;

  /// 数值单位后缀（如 ` px`、` ms`、`×`、`%`）。
  final String valueSuffix;

  /// 按百分比显示（0–1 的设置值 × 100）。
  final bool valuePercent;

  /// 正数带 `+` 号（延迟校准一类的双向量）。
  final bool valueSigned;
  final ValueChanged<double> onChanged;

  /// 生效范围徽标文案（桌面/移动端/通用），为空时不渲染徽标。
  final String? scopeLabel;

  @override
  Widget build(BuildContext context) {
    final scaled = valuePercent ? value * 100 : value;
    final number =
        displayAsInteger
            ? scaled.round().toString()
            : scaled.toStringAsFixed(2);
    final sign = valueSigned && scaled > 0 ? '+' : '';
    // 百分比自带 % 单位，调用方无需重复传后缀。
    final suffix = valuePercent ? '%$valueSuffix' : valueSuffix;
    final display = '$sign$number$suffix';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: TextStyle(color: palette.text)),
              ),
              if (scopeLabel != null) ...[
                const SizedBox(width: 6),
                MusicVisualScopeBadge(palette: palette, label: scopeLabel!),
              ],
              Text(
                display,
                style: TextStyle(
                  color: palette.text.withValues(alpha: 0.86),
                  fontSize: AppTypography.bodySmall,
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
