import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/appearance/application/font_scale_controller.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/anchored_popover.dart';

/// 顶栏字体档位快捷入口。
///
/// 交互结构参照 Reader 重构原型：衬线 "Aa" 入口按钮（边框三态）+ 控件
/// 下方右对齐的直角小面板（等宽小标签 + 一行档位方格、反色选中、点选
/// 即生效关闭）。五档以首格 Auto 表达跟随系统，S/M/L/XL 字母逐格放大
/// 演示档位。
class FontScaleControl extends ConsumerStatefulWidget {
  const FontScaleControl({super.key, this.size = 20, this.color});

  /// 衬线 Aa 字号，沿用各壳层既有图标尺寸（18/20）。
  final double size;

  /// 默认文字色；打开态固定前景色。
  final Color? color;

  @override
  ConsumerState<FontScaleControl> createState() => _FontScaleControlState();
}

class _FontScaleControlState extends ConsumerState<FontScaleControl> {
  final AnchoredPopover _popover = AnchoredPopover();
  bool _hovered = false;

  @override
  void dispose() {
    _popover.close();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final open = _popover.isOpen;
    final idleColor = widget.color ?? colors.onSurfaceVariant;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: AppLocalizations.of(context).fontScaleTitle,
        child: InkWell(
          borderRadius: BorderRadius.zero,
          onTap: _toggle,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              border: Border.all(
                color: open ? colors.onSurface : Colors.transparent,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              'Aa',
              style: TextStyle(
                fontFamily: 'InstrumentSerif',
                fontFamilyFallback: const ['NotoSerifSC'],
                fontSize: widget.size,
                color:
                    open
                        ? colors.onSurface
                        : _hovered
                        ? colors.onSurface
                        : idleColor,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggle() {
    if (_popover.isOpen) {
      _popover.close(onChanged: _refresh);
      return;
    }
    if (isMobilePlatform) {
      unawaited(_showMobileSheet());
      return;
    }
    _popover.open(context, _buildPanel, onChanged: _refresh);
  }

  Future<void> _showMobileSheet() async {
    final preset = ref.read(fontScaleControllerProvider);
    final selected = await showModalBottomSheet<FontScalePreset>(
      context: context,
      builder: (sheetContext) => _FontScaleSheet(current: preset),
    );
    if (selected == null || !mounted) {
      return;
    }
    await ref.read(fontScaleControllerProvider.notifier).setPreset(selected);
  }

  Widget _buildPanel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final current = ref.read(fontScaleControllerProvider);
    final notifier = ref.read(fontScaleControllerProvider.notifier);
    return Material(
      color: colors.surfaceContainerLow,
      shadowColor: colors.shadow.withValues(alpha: 0.55),
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.fontScaleTitle,
              style: TextStyle(
                fontFamily: AppTypography.monoFamily,
                fontFamilyFallback: AppTypography.monoFamilyFallback,
                fontSize: 10,
                letterSpacing: 2,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final preset in FontScalePreset.values) ...[
                  if (preset != FontScalePreset.values.first)
                    const SizedBox(width: 4),
                  _FontScaleCell(
                    preset: preset,
                    selected: preset == current,
                    onTap: () {
                      _popover.close(onChanged: _refresh);
                      unawaited(notifier.setPreset(preset));
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 档位方格：衬线字母逐格放大，选中反色填充。
class _FontScaleCell extends StatelessWidget {
  const _FontScaleCell({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final FontScalePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.zero,
      onTap: onTap,
      child: Container(
        width: 38,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.onSurface : Colors.transparent,
          border: Border.all(
            color: selected ? colors.onSurface : colors.outlineVariant,
          ),
        ),
        child: Text(_label, style: _labelStyle(colors)),
      ),
    );
  }

  String get _label {
    return switch (preset) {
      FontScalePreset.followSystem => 'Auto',
      FontScalePreset.compact => 'S',
      FontScalePreset.standard => 'M',
      FontScalePreset.comfortable => 'L',
      FontScalePreset.large => 'XL',
    };
  }

  TextStyle _labelStyle(ColorScheme colors) {
    final color = selected ? colors.surface : colors.onSurfaceVariant;
    if (preset == FontScalePreset.followSystem) {
      return TextStyle(
        fontFamily: AppTypography.monoFamily,
        fontFamilyFallback: AppTypography.monoFamilyFallback,
        fontSize: 9,
        letterSpacing: 0.5,
        color: color,
      );
    }
    return TextStyle(
      fontFamily: 'InstrumentSerif',
      fontFamilyFallback: const ['NotoSerifSC'],
      fontSize: switch (preset) {
        FontScalePreset.compact => 11.0,
        FontScalePreset.standard => 13.0,
        FontScalePreset.comfortable => 15.0,
        _ => 17.0,
      },
      color: color,
    );
  }
}

/// 移动端底部面板：与桌面面板同构（标签行 + 档位方格行）。
class _FontScaleSheet extends ConsumerWidget {
  const _FontScaleSheet({required this.current});

  final FontScalePreset current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.fontScaleTitle,
              style: TextStyle(
                fontFamily: AppTypography.monoFamily,
                fontFamilyFallback: AppTypography.monoFamilyFallback,
                fontSize: 10,
                letterSpacing: 2,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final preset in FontScalePreset.values) ...[
                  if (preset != FontScalePreset.values.first)
                    const SizedBox(width: 4),
                  _FontScaleCell(
                    preset: preset,
                    selected: preset == current,
                    onTap: () => Navigator.of(context).pop(preset),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
