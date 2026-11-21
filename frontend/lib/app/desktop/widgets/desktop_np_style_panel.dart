import 'dart:async' show Timer, unawaited;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_color_field.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_np_style.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';

part 'desktop_np_style_panel_background.dart';
part 'desktop_np_style_panel_lyrics.dart';
part 'desktop_np_style_panel_editors.dart';
part 'desktop_np_style_panel_controls.dart';

// 面板逐值对齐样例 `npstyle.css` 与 `NpStyle.tsx`：这些字号属于视觉规格，
// 不是可换档的语义层级，集中登记避免散落裸数字。
const _npTitleSize = 16.0;
const _npHeadingSize = 11.0;
const _npLabelSize = 12.5;
const _npChipSize = 11.5;
const _npBadgeSize = 12.0;
const _npGlyphSize = 28.0;
const _npCaptionSize = 15.0;

/// Now Playing 外观全高右侧抽屉（对齐新版样例 `NpStyle.tsx` v4 与 `npstyle.css:162-186`）：
/// 宽 `clamp(380px, 30vw, 440px)`，无圆角，左侧 `1px` 细线，三段固定骨架
/// （顶部标题 + `Background / Lyrics` 双 Tab → 中部独立滚动区 → 底部常驻 Reset）。
class DesktopNpStylePanel extends ConsumerStatefulWidget {
  const DesktopNpStylePanel({required this.onClose, this.hueColor, super.key});

  final VoidCallback onClose;
  final Color? hueColor;

  static const _panel = Color(0xEB0C0F13);
  static const _footerBg = Color(0x990C0F13);
  static const _line = Color(0x18FFFFFF);
  static const _line2 = Color(0x28FFFFFF);
  static const _text = Color(0xFFF2F5F4);
  static const _muted = Color(0x99FFFFFF);

  /// `saturate(1.4)` 的 5×4 颜色矩阵。
  static const List<double> _saturate14 = <double>[
    1.3148,
    -0.286,
    -0.0288,
    0,
    0,
    -0.0852,
    1.114,
    -0.0288,
    0,
    0,
    -0.0852,
    -0.286,
    1.3712,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  @override
  ConsumerState<DesktopNpStylePanel> createState() =>
      _DesktopNpStylePanelState();
}

class _DesktopNpStylePanelState extends ConsumerState<DesktopNpStylePanel> {
  int _tab = 0; // 0 = Background, 1 = Lyrics
  int _lyricTarget = 0; // 0 = Current line, 1 = Other lines

  /// 切换歌词颜料编辑目标（当前行 / 其他行），供拆分出的 part 调用。
  void _selectLyricTarget(int value) => setState(() => _lyricTarget = value);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final style = ref.watch(desktopNpStyleProvider);
    final controller = ref.read(desktopNpStyleProvider.notifier);
    final hue = widget.hueColor ?? skin.accent;
    final isZh = Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('zh');

    final screenWidth = MediaQuery.sizeOf(context).width;
    final drawerWidth =
        screenWidth <= 440
            ? screenWidth
            : (screenWidth * 0.30).clamp(380.0, 440.0);

    return SizedBox(
      width: drawerWidth,
      child: ClipRect(
        child: BackdropFilter.grouped(
          filterConfig: ImageFilterConfig(
            ImageFilter.compose(
              outer: const ColorFilter.matrix(DesktopNpStylePanel._saturate14),
              inner: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            ),
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: DesktopNpStylePanel._panel,
              border: Border(
                left: BorderSide(color: DesktopNpStylePanel._line2),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Color(0xBF000000),
                  blurRadius: 70,
                  spreadRadius: -20,
                  offset: Offset(-12, 0),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 顶部标题栏
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 14, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.desktopNpAppearance,
                          style: DesktopType.panelTitle(
                            DesktopNpStylePanel._text,
                          ).copyWith(
                            fontSize: _npTitleSize,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      DesktopIconButton(
                        icon: DesktopIcons.close,
                        size: 30,
                        iconSize: 16,
                        color: DesktopNpStylePanel._text,
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                ),
                // 固定 Background / Lyrics 双 Tab
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: DesktopNpStylePanel._line),
                    ),
                  ),
                  child: _DarkSeg(
                    labels: <String>[
                      l10n.desktopNpBackground,
                      l10n.desktopNpLyrics,
                    ],
                    index: _tab,
                    keyPrefix: 'desktop-np-tab',
                    onChanged: (value) => setState(() => _tab = value),
                  ),
                ),
                // 中部独立滚动区（Lyrics Tab 顶部吸顶真实 3 行衬线动态预览）
                if (_tab == 1)
                  Container(
                    padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          const Color(0xF70C0F13),
                          const Color(0xCC0C0F13),
                          const Color(0x000C0F13),
                        ],
                        stops: const <double>[0.0, 0.82, 1.0],
                      ),
                    ),
                    child: _LyricLivePreview(style: style, hueColor: hue),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    key: ValueKey<int>(_tab),
                    padding: EdgeInsets.fromLTRB(
                      22,
                      _tab == 1 ? 6 : 16,
                      22,
                      24,
                    ),
                    child:
                        _tab == 0
                            ? _buildBackgroundTab(
                              context,
                              l10n: l10n,
                              isZh: isZh,
                              hue: hue,
                              style: style,
                              controller: controller,
                            )
                            : _buildLyricsTab(
                              context,
                              l10n: l10n,
                              isZh: isZh,
                              style: style,
                              controller: controller,
                            ),
                  ),
                ),
                // 底部常驻 Reset to default
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                  decoration: const BoxDecoration(
                    color: DesktopNpStylePanel._footerBg,
                    border: Border(
                      top: BorderSide(color: DesktopNpStylePanel._line),
                    ),
                  ),
                  child: GestureDetector(
                    onTap: () => unawaited(controller.reset()),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            DesktopIcons.retry,
                            size: 14,
                            color: DesktopNpStylePanel._text,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.desktopNpReset,
                            style: DesktopType.dense(
                              DesktopNpStylePanel._text,
                            ).copyWith(fontSize: _npLabelSize),
                          ),
                        ],
                      ),
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

  Widget _sectionHeading(String text) => Text(
    text.toUpperCase(),
    style: DesktopType.eyebrow(
      Colors.white.withValues(alpha: 0.50),
    ).copyWith(letterSpacing: 1.4, fontSize: _npHeadingSize),
  );

  Widget _fieldLabel(String text) => Text(
    text,
    style: DesktopType.caption(
      DesktopNpStylePanel._text,
    ).copyWith(fontSize: _npLabelSize),
  );

  Widget _toggleRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: DesktopType.caption(
                DesktopNpStylePanel._text,
              ).copyWith(fontSize: _npLabelSize),
            ),
          ),
          _Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _sliderRow({
    required String label,
    required String readout,
    required double value,
    double min = 0,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    final skin = DesktopSkin.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: DesktopType.caption(
                  DesktopNpStylePanel._text,
                ).copyWith(fontSize: _npLabelSize),
              ),
            ),
            Text(
              readout,
              style: DesktopType.numeric(Colors.white.withValues(alpha: 0.55)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        DesktopSlider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          trackColor: Colors.white.withValues(alpha: 0.22),
          fillColor: skin.accent,
          thumbColor: Colors.white,
          thumbAlwaysVisible: true,
          onChanged: onChanged,
        ),
      ],
    );
  }

  String _presetLabel(AppLocalizations l10n, int index) => switch (index) {
    0 => l10n.desktopNpPresetAuto,
    1 => l10n.desktopNpPresetSunset,
    2 => l10n.desktopNpPresetOcean,
    3 => l10n.desktopNpPresetForest,
    4 => l10n.desktopNpPresetRose,
    _ => l10n.desktopNpPresetMono,
  };
}
