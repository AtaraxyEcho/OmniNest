import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_image.dart';
import 'package:omninest/core/widgets/mobile_sheet_semantics.dart';

/// 视觉环境移动端设置（样例 EnvSettings）：根级全覆盖贴底抽屉——
/// 当前环境大卡 + 图库网格（选中打勾 + 上传瓦片）+ 行为开关。
///
/// 抽屉走 `useRootNavigator: true`，而 `showModalBottomSheet` 用
/// `InheritedTheme.capture` 把属主链上的 Theme 冻结进模态子树：抽屉里
/// `Theme.of` 要么拿到没有极性注册的根主题（`MobileEnvPalette.of` 退回暗
/// 基准，于是"浅色模式"成了空操作），要么拿到打开那一刻的旧主题（翻设置
/// 不跟随）。两条都不是要的，所以极性不在自身 Theme 上取，而是按壳层同一
/// 判据现取（外观设置解析出的亮度，即 `mobileEnvPaletteFor` 读的
/// `theme.brightness`），再由 [_MobileEnvPaletteScope] 注册回抽屉子树。
/// modal 背景同时改透明：表面色由抽屉自身画，取值不再冻在打开那一刻。
Future<void> showMobileEnvSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      minHeight: MediaQuery.sizeOf(context).height * 0.6,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder:
        (_) => MobileSheetSemantics(
          child: const _MobileEnvPaletteScope(child: _MobileEnvSettingsSheet()),
        ),
  );
}

/// 抽屉子树的极性注册：与壳层共用 `MobileEnvPalette.resolve`，
/// 亮度来源是外观设置，翻设置即刻跟随（不把 palette 快照进 widget）。
class _MobileEnvPaletteScope extends ConsumerWidget {
  const _MobileEnvPaletteScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = Theme.of(context);
    return Theme(
      data: base.withEnvPalette(
        MobileEnvPalette.resolve(_appearanceBrightness(context, ref)),
      ),
      child: child,
    );
  }

  /// ThemeMode.system 时 MaterialApp 用的就是平台亮度，这里保持同一结果。
  Brightness _appearanceBrightness(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(appearanceControllerProvider)) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
  }
}

class _MobileEnvSettingsSheet extends ConsumerStatefulWidget {
  const _MobileEnvSettingsSheet();

  @override
  ConsumerState<_MobileEnvSettingsSheet> createState() =>
      _MobileEnvSettingsSheetState();
}

class _MobileEnvSettingsSheetState
    extends ConsumerState<_MobileEnvSettingsSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncFromServer();
    });
  }

  void _syncFromServer() {
    ref.read(appBackdropControllerProvider.notifier).syncFromServer();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(appBackdropControllerProvider);
    final state = async.asData?.value;
    final controller = ref.read(appBackdropControllerProvider.notifier);
    final backdrops = state?.backdrops ?? const <AppBackdropAsset>[];
    final selected = state?.selectedBackdrop;
    final enabled = state?.settings.enabled ?? true;

    return DecoratedBox(
      key: const ValueKey<String>('omninest.envSheet.surface'),
      decoration: BoxDecoration(
        color: context.env.sheetSolid,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: context.env.line12)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 抽屉头：眉标 + 衬线标题 + 关闭圆钮（样例 sheet-head）。
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 10, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PREFERENCES',
                          style: TextStyle(
                            fontSize: 8, // ignore: font_size_whitelist
                            height: 1.45,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w700,
                            color: context.env.groupLabelInk,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          l10n.accountEntryEnvironment,
                          style: TextStyle(
                            fontSize: 21, // ignore: font_size_whitelist
                            color: context.env.ink,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 样例 `.sheet-head` 的关闭位是 48 玻璃圆钮（`.icon-button`）+
                  // 同源 close 矢量；裸 IconButton 只有命中区没有控件本体。
                  MobileGlassIconButton(
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    vector: OmniIcons.close,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                children: [
                  // 当前环境大卡（样例 env-current）。
                  _CurrentEnvCard(selected: selected, enabled: enabled),
                  const SizedBox(height: 18),
                  _GroupLabel(l10n.envSheetLibrary),
                  const SizedBox(height: 8),
                  if (backdrops.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text(
                          l10n.envSheetEmpty,
                          style: TextStyle(
                            fontSize: 12, // ignore: font_size_whitelist
                            color: context.env.inkMuted,
                          ),
                        ),
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 7,
                            crossAxisSpacing: 7,
                          ),
                      itemCount: backdrops.length + 1,
                      itemBuilder: (context, index) {
                        if (index == backdrops.length) {
                          return _UploadTile(
                            onTap: () => controller.addBackdropFiles(),
                          );
                        }
                        final backdrop = backdrops[index];
                        final active =
                            selected != null && backdrop.id == selected.id;
                        return _LibraryTile(
                          backdrop: backdrop,
                          active: active,
                          onTap: () => controller.selectBackdrop(backdrop.id),
                        );
                      },
                    ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      l10n.envSheetUploadHint,
                      style: TextStyle(
                        fontSize: 8, // ignore: font_size_whitelist
                        color: context.env.inkFaint,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _GroupLabel(l10n.envSheetBehavior),
                  _BehaviorToggleRow(
                    icon: Icons.image_outlined,
                    label: l10n.envSheetLive,
                    subtitle: l10n.envSheetLiveSub,
                    value: enabled,
                    onChanged: (value) => controller.setEnabled(value),
                  ),
                  _BehaviorToggleRow(
                    icon: Icons.devices_other_rounded,
                    label: l10n.envSheetSeparate,
                    subtitle: l10n.envSheetSeparateSub,
                    value: state?.settings.separateDeviceBackdrops ?? false,
                    onChanged: (value) => controller.setDeviceSeparation(value),
                  ),
                  if (backdrops.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: TextButton(
                        onPressed: () => controller.clearBackdrops(),
                        style: TextButton.styleFrom(
                          foregroundColor: context.env.statusDanger,
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                            side: BorderSide(
                              color: context.env.statusDanger.withValues(
                                alpha: 0.22,
                              ),
                            ),
                          ),
                        ),
                        child: Text(
                          l10n.envSheetClearAll,
                          style: const TextStyle(
                            fontSize: 11, // ignore: font_size_whitelist
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分组眉标（样例 notif-group-label）。
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 8, // ignore: font_size_whitelist
        height: 1.45,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w700,
        color: context.env.groupLabelInk,
      ),
    );
  }
}

/// 当前环境卡（样例 env-current：预览 + 名称 + ACTIVE 徽标）。
class _CurrentEnvCard extends StatelessWidget {
  const _CurrentEnvCard({required this.selected, required this.enabled});

  final AppBackdropAsset? selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 108,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.env.line07,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.env.line09),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox.square(
              dimension: 84,
              child: _EnvPreview(asset: selected),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selected?.title ?? l10n.accountEntryEnvironmentDefault,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13, // ignore: font_size_whitelist
                    fontWeight: FontWeight.w700,
                    color: context.env.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  enabled ? l10n.envSheetLiveSub : l10n.envSheetLive,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9, // ignore: font_size_whitelist
                    color: context.env.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          if (enabled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: context.env.accentInk.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l10n.envSheetActive,
                style: TextStyle(
                  fontSize: 8, // ignore: font_size_whitelist
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: context.env.accentInk,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 环境预览（服务端缩略/内置资产/占位）。
class _EnvPreview extends StatelessWidget {
  const _EnvPreview({required this.asset});

  final AppBackdropAsset? asset;

  @override
  Widget build(BuildContext context) {
    final value = asset;
    if (value == null) {
      return ColoredBox(color: context.env.line12);
    }
    if (value.sourceType == AppBackdropSourceType.bundled) {
      return Image.asset(value.path, fit: BoxFit.cover);
    }
    final thumbnail = value.thumbnailPath;
    if (thumbnail != null && thumbnail.isNotEmpty) {
      return AppBackdropImage(
        url: thumbnail,
        cacheKey: 'env-sheet:${value.id}',
        fit: BoxFit.cover,
        fallbackUrl: value.path.isNotEmpty ? value.path : null,
      );
    }
    if (value.mediaType != AppBackdropMediaType.video &&
        value.path.isNotEmpty) {
      return AppBackdropImage(
        url: value.path,
        cacheKey: 'env-sheet-full:${value.id}',
        fit: BoxFit.cover,
      );
    }
    return ColoredBox(color: context.env.line12);
  }
}

/// 图库瓦片（样例 env-grid：方形圆角 + 选中酸绿描边与打勾）。
class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.backdrop,
    required this.active,
    required this.onTap,
  });

  final AppBackdropAsset backdrop;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? context.env.accentInk : context.env.line09,
              width: active ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _EnvPreview(asset: backdrop),
                if (active)
                  Container(
                    color: Colors.black.withValues(alpha: 0.25),
                    alignment: Alignment.center,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: context.env.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: Color(0xFF172014),
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
}

/// 上传瓦片（样例 env-upload：加号占位）。
class _UploadTile extends StatelessWidget {
  const _UploadTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            color: context.env.surfaceTint,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.env.line09),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 22, color: context.env.inkMuted),
              const SizedBox(height: 5),
              Text(
                l10n.envSheetUpload,
                style: TextStyle(
                  fontSize: 8, // ignore: font_size_whitelist
                  color: context.env.inkFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 行为开关行（样例 notif-toggle-row：图标盒 + 标题/副题 + 酸绿开关）。
class _BehaviorToggleRow extends StatelessWidget {
  const _BehaviorToggleRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.env.accentInk.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: context.env.accentInk),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12, // ignore: font_size_whitelist
                    fontWeight: FontWeight.w600,
                    color: context.env.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 9, // ignore: font_size_whitelist
                    color: context.env.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          MobileEnvSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
