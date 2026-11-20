import 'dart:async' show unawaited;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_np_style.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/desktop_routes.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';

/// Now Playing 外观面板（样例 `.nps`）：360 宽的暗色浮层，分预设、背景、
/// 遮罩与歌词四段；所有改动即时生效并落本地偏好。
///
/// 面板恒为暗色（正在播放是沉浸舞台），因此控件用显式白色系，不读主题
/// 的 raise/line —— 浅色主题下那些令牌在暗底上不可见。
class DesktopNpStylePanel extends ConsumerWidget {
  const DesktopNpStylePanel({required this.onClose, super.key});

  final VoidCallback onClose;

  static const _panel = Color(0xE60E1216);

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
  static const _line = Color(0x24FFFFFF);
  static const _text = Color(0xFFE8ECEA);
  static const _muted = Color(0x99FFFFFF);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final style = ref.watch(desktopNpStyleProvider);
    final controller = ref.read(desktopNpStyleProvider.notifier);

    // 样例 `npstyle.css:20`：宽 `min(360, 100vw-32)`、高 `calc(100%-150px)`、
    // `blur(26) saturate(1.4)`、投影 `0 30px 70px -20px rgba(0,0,0,.75)`。
    final screen = MediaQuery.sizeOf(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: screen.width - 32 < 360 ? screen.width - 32 : 360,
        maxHeight: screen.height - 150,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter.grouped(
          filterConfig: ImageFilterConfig(
            ImageFilter.compose(
              outer: const ColorFilter.matrix(_saturate14),
              inner: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _line),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.75),
                  blurRadius: 70,
                  spreadRadius: -20,
                  offset: const Offset(0, 30),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 10, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.desktopNpAppearance,
                          style: DesktopType.panelTitle(_text),
                        ),
                      ),
                      DesktopIconButton(
                        icon: DesktopIcons.close,
                        size: 28,
                        iconSize: 14,
                        color: _muted,
                        onPressed: onClose,
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label(l10n.desktopNpPresets),
                        const SizedBox(height: 8),
                        // 样例 `npstyle.css:23`：6 列等宽网格，色块 `width:100%` +
                        // `aspect-ratio:1` + r12，下方带名称；不再是圆形色点。
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < DesktopNpPreset.all.length; i++)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right:
                                        i == DesktopNpPreset.all.length - 1
                                            ? 0
                                            : 8,
                                  ),
                                  child: GestureDetector(
                                    onTap:
                                        () => controller.apply(
                                          style.copyWith(
                                            preset: i,
                                            background:
                                                style.background ==
                                                        DesktopNpBackground
                                                            .cover
                                                    ? DesktopNpBackground
                                                        .gradient
                                                    : style.background,
                                          ),
                                        ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        AspectRatio(
                                          aspectRatio: 1,
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  _presetTop(skin, i),
                                                  DesktopNpPreset.all[i].bottom,
                                                ],
                                              ),
                                              border: Border.all(
                                                color:
                                                    style.preset == i
                                                        ? Colors.white
                                                        : Colors.white
                                                            .withValues(
                                                              alpha: 0.18,
                                                            ),
                                                width:
                                                    style.preset == i ? 2 : 1,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _presetLabel(l10n, i),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: DesktopType.nano(_muted),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _label(l10n.desktopNpBackground),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final entry
                                in <DesktopNpBackground, String>{
                                  DesktopNpBackground.cover:
                                      l10n.desktopNpCover,
                                  DesktopNpBackground.aurora:
                                      l10n.desktopNpAurora,
                                  DesktopNpBackground.spectrum:
                                      l10n.desktopNpSpectrum,
                                  DesktopNpBackground.library:
                                      l10n.desktopNpLibrary,
                                  DesktopNpBackground.gradient:
                                      l10n.desktopNpGradient,
                                  DesktopNpBackground.plain:
                                      l10n.desktopNpPlain,
                                }.entries)
                              _Pill(
                                label: entry.value,
                                selected: style.background == entry.key,
                                onTap:
                                    () => controller.apply(
                                      style.copyWith(background: entry.key),
                                    ),
                              ),
                          ],
                        ),
                        if (style.background == DesktopNpBackground.library)
                          _WallPicker(
                            style: style,
                            onSelect: (id) {
                              // 样例 `WallPicker`：点缩略图既记住 NP 的选择，
                              // 也把全局壁纸切到同一张，背景才真的会变。
                              unawaited(
                                ref
                                    .read(
                                      appBackdropControllerProvider.notifier,
                                    )
                                    .selectBackdrop(id),
                              );
                              controller.apply(style.copyWith(wallId: id));
                            },
                          ),
                        const SizedBox(height: 18),
                        _label(l10n.desktopNpMask),
                        const SizedBox(height: 8),
                        _sliderRow(
                          context,
                          label: l10n.desktopNpDarkness,
                          value: style.mask,
                          max: 80,
                          onChanged:
                              (value) =>
                                  controller.apply(style.copyWith(mask: value)),
                        ),
                        _sliderRow(
                          context,
                          label: l10n.desktopNpBlur,
                          value: style.blur,
                          max: 40,
                          onChanged:
                              (value) =>
                                  controller.apply(style.copyWith(blur: value)),
                        ),
                        const SizedBox(height: 12),
                        _label(l10n.desktopNpLyrics),
                        const SizedBox(height: 8),
                        _LyricAppearancePreview(style: style),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              l10n.desktopNpSize,
                              style: DesktopType.caption(_muted),
                            ),
                            const Spacer(),
                            for (
                              var i = 0;
                              i < desktopNpLyricScales.length;
                              i++
                            )
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: _Pill(
                                  label: const ['S', 'M', 'L'][i],
                                  selected:
                                      (style.lyricScale -
                                              desktopNpLyricScales[i])
                                          .abs() <
                                      0.01,
                                  onTap:
                                      () => controller.apply(
                                        style.copyWith(
                                          lyricScale: desktopNpLyricScales[i],
                                        ),
                                      ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.desktopNpGlow,
                                style: DesktopType.caption(_muted),
                              ),
                            ),
                            _Switch(
                              value: style.glow,
                              onChanged:
                                  (value) => controller.apply(
                                    style.copyWith(glow: value),
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.desktopNpWordFill,
                                style: DesktopType.caption(_muted),
                              ),
                            ),
                            _Switch(
                              value: style.wordFill,
                              onChanged:
                                  (value) => controller.apply(
                                    style.copyWith(wordFill: value),
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.desktopNpBrush,
                                style: DesktopType.caption(_muted),
                              ),
                            ),
                            for (
                              var i = 0;
                              i < DesktopNpBrush.values.length;
                              i++
                            )
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: _BrushDot(
                                  color: DesktopNpBrush.values[i].color,
                                  selected: style.brush == i,
                                  onTap:
                                      () => controller.apply(
                                        style.copyWith(brush: i),
                                      ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _label(l10n.desktopNpPaint),
                        const SizedBox(height: 8),
                        // 样例 `.nps-split`：两枚整行按钮，不用并排分段控件——
                        // 360 宽面板里长文案会把 Row 顶出去。
                        _SplitChoice(
                          label: l10n.desktopNpWholeLine,
                          selected: !style.splitPaint,
                          onTap:
                              () => controller.apply(
                                style.copyWith(splitPaint: false),
                              ),
                        ),
                        const SizedBox(height: 6),
                        _SplitChoice(
                          label: l10n.desktopNpHalves,
                          selected: style.splitPaint,
                          onTap:
                              () => controller.apply(
                                style.copyWith(splitPaint: true),
                              ),
                        ),
                        if (style.splitPaint) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.desktopNpLowerBrush,
                                  style: DesktopType.caption(_muted),
                                ),
                              ),
                              for (
                                var i = 0;
                                i < DesktopNpBrush.values.length;
                                i++
                              )
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: _BrushDot(
                                    color: DesktopNpBrush.values[i].color,
                                    selected: style.lowerBrush == i,
                                    onTap:
                                        () => controller.apply(
                                          style.copyWith(lowerBrush: i),
                                        ),
                                  ),
                                ),
                            ],
                          ),
                          _sliderRow(
                            context,
                            label: l10n.desktopNpSplitPos,
                            value: style.splitPos.toDouble(),
                            max: 100,
                            onChanged:
                                (value) => controller.apply(
                                  style.copyWith(
                                    splitPos: value.round().clamp(5, 95),
                                  ),
                                ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        DesktopButton(
                          label: l10n.desktopNpReset,
                          variant: DesktopButtonVariant.glass,
                          onPressed: controller.reset,
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

  Widget _label(String text) => Text(
    text.toUpperCase(),
    style: DesktopType.eyebrow(_muted).copyWith(letterSpacing: 1.4),
  );

  Widget _sliderRow(
    BuildContext context, {
    required String label,
    required double value,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 74,
          child: Text(label, style: DesktopType.caption(_muted)),
        ),
        Expanded(
          child: DesktopSlider(
            value: value,
            max: max,
            trackColor: Colors.white.withValues(alpha: 0.18),
            fillColor: Colors.white,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '${value.round()}',
            textAlign: TextAlign.right,
            style: DesktopType.numeric(_muted),
          ),
        ),
      ],
    );
  }

  Color _presetTop(DesktopSkin skin, int index) =>
      index == 0 ? skin.accent : DesktopNpPreset.all[index].top;

  String _presetLabel(AppLocalizations l10n, int index) => switch (index) {
    0 => l10n.desktopNpPresetAuto,
    1 => l10n.desktopNpPresetSunset,
    2 => l10n.desktopNpPresetOcean,
    3 => l10n.desktopNpPresetForest,
    4 => l10n.desktopNpPresetRose,
    _ => l10n.desktopNpPresetMono,
  };
}

/// 参照样例 `LyricPreview` 的轻量预览：只绘制三行色带，不启动独立动画，
/// 保证拖动滑杆时面板不会再创建一棵高成本的歌词列表。
class _LyricAppearancePreview extends StatelessWidget {
  const _LyricAppearancePreview({required this.style});

  final DesktopNpStyle style;

  @override
  Widget build(BuildContext context) {
    final active = DesktopNpBrush.values[style.brush.clamp(0, 4)].color;
    final lower = DesktopNpBrush.values[style.lowerBrush.clamp(0, 4)].color;
    final inactive = Colors.white.withValues(alpha: 0.28);
    final activeDecoration = BoxDecoration(
      gradient:
          style.splitPaint
              ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [
                  style.splitPos.clamp(5, 95) / 100,
                  style.splitPos.clamp(5, 95) / 100,
                ],
                colors: [active, lower],
              )
              : null,
      color: style.splitPaint ? null : active,
      borderRadius: BorderRadius.circular(4),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DesktopNpStylePanel._line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FractionallySizedBox(
            widthFactor: 0.58,
            child: Container(height: 8, decoration: activeDecoration),
          ),
          const SizedBox(height: 8),
          FractionallySizedBox(
            widthFactor: 0.82,
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: inactive,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FractionallySizedBox(
            widthFactor: 0.66,
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: inactive.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: DesktopMotion.of(context, DesktopMotion.fast),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color:
                selected ? Colors.white : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: DesktopType.chip(
            selected ? const Color(0xFF0A0C0E) : const Color(0xCCFFFFFF),
          ).copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: DesktopMotion.of(context, DesktopMotion.fast),
        width: 38,
        height: 22,
        padding: const EdgeInsets.all(3),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: value ? Colors.white : Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: value ? const Color(0xFF0A0C0E) : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// 歌词填充模式的一枚整行选项（样例 `.nps-split button`）。
class _SplitChoice extends StatelessWidget {
  const _SplitChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0x22FFFFFF) : const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                selected
                    ? DesktopNpStylePanel._text
                    : DesktopNpStylePanel._line,
          ),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: DesktopType.dense(
              selected ? DesktopNpStylePanel._text : DesktopNpStylePanel._muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _BrushDot extends StatelessWidget {
  const _BrushDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 2 : 1,
          ),
          boxShadow:
              selected
                  ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 10,
                    ),
                  ]
                  : null,
        ),
      ),
    );
  }
}

/// 样例 `NpStyle.tsx:132` 的 `WallPicker`：壁纸库缩略图网格 + 上传 +
/// 「Manage library」入口。选中项同时写回 `wallId` 与全局壁纸设置。
class _WallPicker extends ConsumerWidget {
  const _WallPicker({required this.style, required this.onSelect});

  final DesktopNpStyle style;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(appBackdropControllerProvider).asData?.value;
    final items = state?.backdrops ?? const <AppBackdropAsset>[];
    final selectedId = style.wallId ?? state?.selectedBackdrop?.id;
    final current = items.where((asset) => asset.id == selectedId).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final asset in items)
              GestureDetector(
                onTap: () => onSelect(asset.id),
                child: Container(
                  width: 62,
                  height: 44,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color:
                          asset.id == selectedId
                              ? Colors.white
                              : DesktopNpStylePanel._line,
                      width: asset.id == selectedId ? 2 : 1,
                    ),
                  ),
                  child: BackdropTilePreview(backdrop: asset),
                ),
              ),
            GestureDetector(
              onTap:
                  () => unawaited(
                    ref
                        .read(appBackdropControllerProvider.notifier)
                        .addBackdropFiles(),
                  ),
              child: Container(
                width: 62,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DesktopNpStylePanel._line),
                  color: Colors.white.withValues(alpha: 0.06),
                ),
                child: const Icon(
                  DesktopIcons.plus,
                  size: 18,
                  color: DesktopNpStylePanel._muted,
                ),
              ),
            ),
          ],
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.desktopNpWallEmpty,
              style: DesktopType.caption(DesktopNpStylePanel._muted),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                current?.title ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DesktopType.caption(DesktopNpStylePanel._muted),
              ),
            ),
            GestureDetector(
              onTap: () => desktopPush(context, DesktopRoutes.settingsBackdrop),
              child: Text(
                l10n.desktopNpManageLibrary,
                style: DesktopType.caption(Colors.white),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
