import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/appearance/application/font_scale_controller.dart';
import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_overlays.dart';
import 'package:omninest/app/desktop/desktop_shell_state.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/locale/application/locale_controller.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 外观设置（样例 Settings → Appearance / Atmosphere）。
///
/// 每一项都即时生效并落设备本地：主题、强调色、环境光、减动效、
/// 紧凑密度、语言与文字档位。桌面壳层自己消费这些值，因此改动
/// 不需要重进页面就能看到。
class DesktopAppearanceSheet extends ConsumerWidget {
  const DesktopAppearanceSheet({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final appearance = ref.watch(desktopAppearanceProvider);
    final controller = ref.read(desktopAppearanceProvider.notifier);
    final themeMode = ref.watch(appearanceControllerProvider);
    final locale = ref.watch(localeControllerProvider);
    final fontScale = ref.watch(fontScaleControllerProvider);

    Widget row({
      required String title,
      required String hint,
      required Widget trailing,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: skin.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: DesktopType.denseStrong(skin.text)),
                  const SizedBox(height: 2),
                  Text(hint, style: DesktopType.caption(skin.text3)),
                ],
              ),
            ),
            const SizedBox(width: 20),
            trailing,
          ],
        ),
      );
    }

    return DesktopModal(
      width: 560,
      onClose: onClose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopModalHead(
            eyebrow: l10n.desktopNavSettings,
            title: l10n.desktopAppearance,
            onClose: onClose,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.desktopAppearanceHint,
                  style: DesktopType.dense(skin.text2),
                ),
                const SizedBox(height: 16),
                DesktopCard(
                  title: l10n.desktopTheme,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Row(
                    children: [
                      for (final mode in ThemeMode.values)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: _ThemeCard(
                              mode: mode,
                              selected: themeMode == mode,
                              onTap:
                                  () => ref
                                      .read(
                                        appearanceControllerProvider.notifier,
                                      )
                                      .setThemeMode(mode),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                DesktopCard(
                  title: l10n.desktopAccent,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.desktopAccentHint,
                        style: DesktopType.caption(skin.text3),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final accent in DesktopAccent.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: _AccentSwatch(
                                accent: accent,
                                selected: appearance.accent == accent,
                                label: switch (accent) {
                                  DesktopAccent.sage => l10n.desktopAccentSage,
                                  DesktopAccent.mist => l10n.desktopAccentMist,
                                  DesktopAccent.copper =>
                                    l10n.desktopAccentCopper,
                                  DesktopAccent.iris => l10n.desktopAccentIris,
                                },
                                onTap: () => controller.setAccent(accent),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                DesktopCard(
                  title: l10n.desktopAtmosphere,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      row(
                        title: l10n.desktopAmbientLight,
                        hint: l10n.desktopAmbientHint,
                        trailing: SizedBox(
                          width: 230,
                          child: Row(
                            children: [
                              Expanded(
                                child: DesktopSlider(
                                  value: appearance.ambient,
                                  max: 100,
                                  onChanged: controller.setAmbient,
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 44,
                                child: Text(
                                  l10n.desktopPercentValue(
                                    appearance.ambient.round(),
                                  ),
                                  textAlign: TextAlign.right,
                                  style: DesktopType.numeric(skin.text),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      row(
                        title: l10n.desktopReduceMotion,
                        hint: l10n.desktopReduceMotionHint,
                        trailing: DesktopToggle(
                          value: appearance.reduceMotion,
                          label: l10n.desktopReduceMotion,
                          onChanged: controller.setReduceMotion,
                        ),
                      ),
                      row(
                        title: l10n.desktopCompactDensity,
                        hint: l10n.desktopCompactHint,
                        trailing: DesktopToggle(
                          value: appearance.compact,
                          label: l10n.desktopCompactDensity,
                          onChanged: controller.setCompact,
                        ),
                      ),
                    ],
                  ),
                ),
                DesktopCard(
                  title: l10n.desktopLanguage,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      row(
                        title: l10n.desktopLanguage,
                        hint: l10n.desktopLanguageHint,
                        trailing: DesktopSeg<String>(
                          options: const ['zh', 'en'],
                          value: locale,
                          small: true,
                          labelOf: (code) => code == 'zh' ? '简体中文' : 'English',
                          onChanged:
                              (code) => ref
                                  .read(localeControllerProvider.notifier)
                                  .setLanguage(code),
                        ),
                      ),
                      row(
                        title: l10n.desktopTextSize,
                        hint: l10n.desktopTextSizeHint,
                        trailing: SizedBox(
                          width: 230,
                          child: Row(
                            children: [
                              Expanded(
                                child: DesktopSlider(
                                  value:
                                      ((fontScale.percent ?? 100) - 85)
                                          .clamp(0, 40)
                                          .toDouble(),
                                  max: 40,
                                  onChanged: (value) {
                                    final percent =
                                        85 + (value / 5).round() * 5;
                                    ref
                                        .read(
                                          fontScaleControllerProvider.notifier,
                                        )
                                        .setPreset(
                                          FontScalePreset.fromPercent(percent),
                                        );
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 44,
                                child: Text(
                                  l10n.desktopPercentValue(
                                    fontScale.percent ?? 100,
                                  ),
                                  textAlign: TextAlign.right,
                                  style: DesktopType.numeric(skin.text),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: DesktopButton(
                    label: l10n.desktopDone,
                    variant: DesktopButtonVariant.primary,
                    onPressed: onClose,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final l10n = AppLocalizations.of(context);
    final label = switch (mode) {
      ThemeMode.dark => l10n.desktopThemeDark,
      ThemeMode.light => l10n.desktopThemeLight,
      ThemeMode.system => l10n.desktopThemeSystem,
    };
    return DesktopHover(
      builder:
          (context, hovered) => GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: MotionToken.reduced(context, MotionToken.fast),
              curve: MotionToken.curve,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color:
                      selected
                          ? skin.accent
                          : hovered
                          ? skin.line2
                          : skin.line,
                  width: DesktopMetrics.hairlineStrong,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 84,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CustomPaint(
                        painter: _ThemePreviewPainter(mode: mode, skin: skin),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: DesktopType.denseStrong(skin.text),
                        ),
                      ),
                      if (selected)
                        Icon(DesktopIcons.check, size: 14, color: skin.accent),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
  }
}

class _ThemePreviewPainter extends CustomPainter {
  const _ThemePreviewPainter({required this.mode, required this.skin});

  final ThemeMode mode;
  final DesktopSkin skin;

  @override
  void paint(Canvas canvas, Size size) {
    final dark = DesktopSkin.resolve(isDark: true, accent: DesktopAccent.sage);
    final light = DesktopSkin.resolve(
      isDark: false,
      accent: DesktopAccent.sage,
    );
    void half(Rect rect, DesktopSkin palette) {
      canvas.drawRect(rect, Paint()..color = palette.bg);
      final rail = Rect.fromLTWH(
        rect.left + 8,
        rect.top + 8,
        22,
        rect.height - 16,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rail, const Radius.circular(6)),
        Paint()..color = palette.raise3,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            rect.left + 36,
            rect.top + 8,
            rect.width * 0.34,
            rect.height * 0.36,
          ),
          const Radius.circular(6),
        ),
        Paint()..color = palette.accent.withValues(alpha: 0.55),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            rect.left + 36,
            rect.bottom - 8 - rect.height * 0.38,
            rect.width * 0.58,
            rect.height * 0.38,
          ),
          const Radius.circular(6),
        ),
        Paint()..color = palette.raise3,
      );
    }

    switch (mode) {
      case ThemeMode.dark:
        half(Offset.zero & size, dark);
      case ThemeMode.light:
        half(Offset.zero & size, light);
      case ThemeMode.system:
        final mid = size.width / 2;
        half(Rect.fromLTWH(0, 0, mid, size.height), dark);
        half(Rect.fromLTWH(mid, 0, size.width - mid, size.height), light);
    }
  }

  @override
  bool shouldRepaint(_ThemePreviewPainter oldDelegate) =>
      oldDelegate.mode != mode || oldDelegate.skin.accent != skin.accent;
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final DesktopAccent accent;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final tint = accent.resolve(isDark: skin.isDark);
    return DesktopHover(
      builder:
          (context, hovered) => GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: MotionToken.reduced(context, MotionToken.fast),
              curve: MotionToken.curve,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color:
                    selected
                        ? skin.raise2
                        : hovered
                        ? skin.raise
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? skin.line2 : Colors.transparent,
                  width: DesktopMetrics.hairlineStrong,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    duration: MotionToken.reduced(context, MotionToken.fast),
                    curve: MotionToken.curve,
                    scale: selected ? 1.12 : 1,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: tint,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: tint.withValues(alpha: 0.45),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                            spreadRadius: -4,
                          ),
                        ],
                        border:
                            selected
                                ? Border.all(color: skin.text2, width: 2)
                                : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: DesktopType.caption(
                      selected ? skin.text : skin.text2,
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}
