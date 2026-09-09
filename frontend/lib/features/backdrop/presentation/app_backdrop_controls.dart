import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_video_session.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_palette.dart';

/// 应用背景设置面板中的操作按钮。
class AppBackdropActionButton extends StatelessWidget {
  const AppBackdropActionButton({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final AppBackdropPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: palette.surfaceContainer.withValues(
              alpha: onTap == null ? 0.45 : 1.0,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.outline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: palette.text, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: palette.text,
                  fontSize: AppTypography.bodyMedium,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 应用背景设置面板中的显示与设备控制区。
class AppBackdropControls extends StatelessWidget {
  const AppBackdropControls({
    required this.palette,
    required this.state,
    required this.notifier,
    super.key,
  });

  final AppBackdropPalette palette;
  final AppBackdropState state;
  final AppBackdropController notifier;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = state.settings;
    return Material(
      color: palette.surfaceContainer,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.outline),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.enabled,
                onChanged:
                    state.selectedBackdrop == null ? null : notifier.setEnabled,
                title: Text(
                  l10n.portalLocalBackdropEnable,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  l10n.portalLocalBackdropEnableHint,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: AppTypography.bodySmall,
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.separateDeviceBackdrops,
                onChanged: notifier.setDeviceSeparation,
                title: Text(
                  l10n.portalLocalBackdropSeparateDevices,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  l10n.portalLocalBackdropSeparateDevicesHint,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: AppTypography.bodySmall,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child:
                    settings.separateDeviceBackdrops
                        ? _BackdropTargetNotice(
                          key: ValueKey(state.selectionTarget),
                          palette: palette,
                          target: state.selectionTarget,
                        )
                        : const SizedBox.shrink(),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.portalLocalBackdropFit,
                style: TextStyle(
                  color: palette.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<AppBackdropFit>(
                style: ButtonStyle(
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return palette.accent;
                    }
                    return palette.text;
                  }),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return palette.accent.withValues(alpha: 0.16);
                    }
                    return palette.surfaceContainer;
                  }),
                  side: WidgetStatePropertyAll(
                    BorderSide(color: palette.outline),
                  ),
                ),
                segments: [
                  ButtonSegment(
                    value: AppBackdropFit.cover,
                    label: Text(l10n.portalLocalBackdropFitCover),
                  ),
                  ButtonSegment(
                    value: AppBackdropFit.contain,
                    label: Text(l10n.portalLocalBackdropFitContain),
                  ),
                  ButtonSegment(
                    value: AppBackdropFit.fill,
                    label: Text(l10n.portalLocalBackdropFitFill),
                  ),
                ],
                selected: {settings.fit},
                onSelectionChanged: (value) => notifier.setFit(value.first),
              ),
              if (settings.fit == AppBackdropFit.cover) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.portalLocalBackdropAlignment,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                SegmentedButton<AppBackdropAlignment>(
                  style: ButtonStyle(
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return palette.accent;
                      }
                      return palette.text;
                    }),
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return palette.accent.withValues(alpha: 0.16);
                      }
                      return palette.surfaceContainer;
                    }),
                    side: WidgetStatePropertyAll(
                      BorderSide(color: palette.outline),
                    ),
                  ),
                  segments: [
                    ButtonSegment(
                      value: AppBackdropAlignment.top,
                      label: Text(l10n.portalLocalBackdropAlignTop),
                    ),
                    ButtonSegment(
                      value: AppBackdropAlignment.center,
                      label: Text(l10n.portalLocalBackdropAlignCenter),
                    ),
                    ButtonSegment(
                      value: AppBackdropAlignment.bottom,
                      label: Text(l10n.portalLocalBackdropAlignBottom),
                    ),
                  ],
                  selected: {settings.alignment},
                  onSelectionChanged:
                      (value) => notifier.setAlignment(value.first),
                ),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.videoMuted,
                onChanged: notifier.setVideoMuted,
                title: Text(
                  l10n.portalLocalBackdropVideoMuted,
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (state.selectedBackdrop?.isVideo == true) ...[
                const SizedBox(height: 8),
                AppBackdropActionButton(
                  palette: palette,
                  icon: Icons.replay_rounded,
                  label: l10n.portalLocalBackdropRetryPlayback,
                  onTap:
                      () => AppBackdropVideoSession.retryPath(
                        state.selectedBackdrop!.path,
                      ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                l10n.portalLocalBackdropLocalOnly,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: AppTypography.bodySmall,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackdropTargetNotice extends StatelessWidget {
  const _BackdropTargetNotice({
    required this.palette,
    required this.target,
    super.key,
  });

  final AppBackdropPalette palette;
  final AppBackdropSelectionTarget target;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mobile = target == AppBackdropSelectionTarget.mobile;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            mobile ? Icons.smartphone_rounded : Icons.desktop_windows_rounded,
            color: palette.accent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mobile
                  ? l10n.portalLocalBackdropCurrentMobile
                  : l10n.portalLocalBackdropCurrentDesktop,
              style: TextStyle(
                color: palette.muted,
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
