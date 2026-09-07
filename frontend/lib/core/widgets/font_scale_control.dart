import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/appearance/application/font_scale_controller.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/utils/platform_helper.dart';

/// 顶栏字体档位快捷入口：桌面端弹出锚定菜单，移动端弹出底部面板。
///
/// 与设置页共享 [fontScaleControllerProvider] 单一状态源，档位切换经
/// 根部 ComposedScaler 即时全局生效。
class FontScaleControl extends ConsumerWidget {
  const FontScaleControl({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: AppLocalizations.of(context).fontScaleTitle,
      onPressed: () => unawaited(_openPanel(context, ref)),
      icon: Icon(Icons.format_size_rounded, size: size, color: color),
    );
  }

  Future<void> _openPanel(BuildContext context, WidgetRef ref) async {
    if (isMobilePlatform) {
      await showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => const _FontScaleSheet(),
      );
      return;
    }
    final RenderBox button = context.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(const Offset(0, 8)),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );
    final selected = await showMenu<FontScalePreset>(
      context: context,
      position: position,
      constraints: const BoxConstraints(minWidth: 240),
      items: _buildMenuItems(context, ref),
    );
    if (selected == null || !context.mounted) {
      return;
    }
    await ref.read(fontScaleControllerProvider.notifier).setPreset(selected);
  }

  List<PopupMenuEntry<FontScalePreset>> _buildMenuItems(
    BuildContext context,
    WidgetRef ref,
  ) {
    final l10n = AppLocalizations.of(context);
    final current = ref.read(fontScaleControllerProvider);
    return [
      PopupMenuItem<FontScalePreset>(
        enabled: false,
        height: 36,
        child: Text(
          l10n.fontScaleTitle,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
      for (final preset in FontScalePreset.values)
        PopupMenuItem<FontScalePreset>(
          value: preset,
          height: 44,
          child: _FontScaleOptionRow(
            preset: preset,
            selected: preset == current,
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem<FontScalePreset>(
        enabled: false,
        height: 64,
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: _FontScalePreview(preset: current),
        ),
      ),
    ];
  }
}

/// 移动端底部面板，选项与预览和桌面菜单一致。
class _FontScaleSheet extends ConsumerWidget {
  const _FontScaleSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(fontScaleControllerProvider);
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
              child: Text(
                l10n.fontScaleTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final preset in FontScalePreset.values)
              ListTile(
                title: _FontScaleOptionRow(
                  preset: preset,
                  selected: preset == current,
                ),
                onTap:
                    preset == current
                        ? null
                        : () => unawaited(
                          ref
                              .read(fontScaleControllerProvider.notifier)
                              .setPreset(preset),
                        ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: _FontScalePreview(preset: current),
            ),
          ],
        ),
      ),
    );
  }
}

class _FontScaleOptionRow extends StatelessWidget {
  const _FontScaleOptionRow({required this.preset, required this.selected});

  final FontScalePreset preset;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scale = preset.scale;
    return Row(
      children: [
        SizedBox(
          width: 28,
          child:
              selected
                  ? Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  )
                  : null,
        ),
        Text(presetLabel(l10n)),
        if (scale != null) ...[
          const SizedBox(width: 8),
          Text(
            '${(scale * 100).round()}%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  String presetLabel(AppLocalizations l10n) {
    return switch (preset) {
      FontScalePreset.followSystem => l10n.fontScaleFollowSystem,
      FontScalePreset.compact => l10n.fontScaleCompact,
      FontScalePreset.standard => l10n.fontScaleStandard,
      FontScalePreset.comfortable => l10n.fontScaleComfortable,
      FontScalePreset.large => l10n.fontScaleLarge,
    };
  }
}

class _FontScalePreview extends StatelessWidget {
  const _FontScalePreview({required this.preset});

  final FontScalePreset preset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                preset.scale ?? MediaQuery.textScalerOf(context).scale(1),
              ),
            ),
            child: Text(
              l10n.fontScalePreviewSample,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, color: colors.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}
