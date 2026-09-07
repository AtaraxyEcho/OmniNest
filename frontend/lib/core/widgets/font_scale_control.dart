import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/appearance/application/font_scale_controller.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/utils/platform_helper.dart';

/// 顶栏字体档位快捷入口：桌面端弹出锚定菜单，移动端弹出底部面板。
///
/// 仅呈现五档名称与选中态勾选；与设置页共享 [fontScaleControllerProvider]
/// 单一状态源，档位切换经根部 ComposedScaler 即时全局生效。
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
    final notifier = ref.read(fontScaleControllerProvider.notifier);
    final current = ref.read(fontScaleControllerProvider);
    if (isMobilePlatform) {
      final selected = await showModalBottomSheet<FontScalePreset>(
        context: context,
        builder: (sheetContext) => _FontScaleSheet(current: current),
      );
      if (selected == null) {
        return;
      }
      await notifier.setPreset(selected);
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
      constraints: const BoxConstraints(minWidth: 168),
      items: [
        for (final preset in FontScalePreset.values)
          PopupMenuItem<FontScalePreset>(
            value: preset,
            height: 44,
            child: _FontScaleOptionRow(
              preset: preset,
              selected: preset == current,
            ),
          ),
      ],
    );
    if (selected == null) {
      return;
    }
    await notifier.setPreset(selected);
  }
}

/// 移动端底部面板，选项与桌面菜单一致。
class _FontScaleSheet extends StatelessWidget {
  const _FontScaleSheet({required this.current});

  final FontScalePreset current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final preset in FontScalePreset.values)
              ListTile(
                title: _FontScaleOptionRow(
                  preset: preset,
                  selected: preset == current,
                ),
                onTap: () {
                  Navigator.of(context).pop(preset);
                },
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
        Text(presetLabel(AppLocalizations.of(context))),
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
