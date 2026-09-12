import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_models.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';

/// 按内容意图组织的桌面端 Music Deck 导航。
class MusicDeckNavigation extends StatelessWidget {
  const MusicDeckNavigation({
    required this.selected,
    required this.onSelected,
    required this.compact,
    required this.canManage,
    required this.connectedPlatformCount,
    required this.onManageAccounts,
    super.key,
  });

  final MusicDeckSection selected;
  final ValueChanged<MusicDeckSection> onSelected;
  final bool compact;
  final bool canManage;
  final int connectedPlatformCount;
  final VoidCallback onManageAccounts;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.musicColors;
    return SizedBox(
      width: compact ? 76 : 216,
      child: MusicDeckGlass(
        opacity: 0.18,
        blur: 12,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            if (!compact)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 18),
                child: Row(
                  children: [
                    Icon(
                      Icons.multitrack_audio_rounded,
                      color: colors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      l10n.musicDeckTitle,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: AppTypography.titleMedium,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            for (final section in MusicDeckSection.values)
              if (section != MusicDeckSection.localManagement || canManage)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: _MusicDeckDestination(
                    section: section,
                    selected: selected == section,
                    compact: compact,
                    onTap: () => onSelected(section),
                  ),
                ),
            const Spacer(),
            Divider(color: colors.outline),
            Tooltip(
              message: l10n.musicDeckManageAccounts,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: onManageAccounts,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisAlignment:
                        compact
                            ? MainAxisAlignment.center
                            : MainAxisAlignment.start,
                    children: [
                      Badge(
                        isLabelVisible: connectedPlatformCount > 0,
                        label: Text('$connectedPlatformCount'),
                        child: Icon(
                          Icons.cloud_done_outlined,
                          color: colors.onSurfaceVariant,
                          size: 20,
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.musicDeckAccounts,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: AppTypography.bodySmall,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MusicDeckDestination extends StatelessWidget {
  const _MusicDeckDestination({
    required this.section,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final MusicDeckSection section;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = section.label(AppLocalizations.of(context));
    final colors = context.musicColors;
    return Tooltip(
      message: compact ? label : '',
      child: Material(
        color: selected ? colors.selectedBg : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: SizedBox(
            height: 42,
            child: Row(
              mainAxisAlignment:
                  compact ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                if (!compact) const SizedBox(width: 11),
                Icon(
                  selected ? section.selectedIcon : section.icon,
                  size: 19,
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                ),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color:
                            selected
                                ? colors.onSurface
                                : colors.onSurfaceVariant,
                        fontSize: AppTypography.bodyMedium,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 移动端主导航只保留高频在线音乐入口。
class MusicDeckMobileNavigation extends StatelessWidget {
  const MusicDeckMobileNavigation({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final MusicDeckSection selected;
  final ValueChanged<MusicDeckSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final primary = const <MusicDeckSection>[
      MusicDeckSection.home,
      MusicDeckSection.library,
      MusicDeckSection.favorites,
      MusicDeckSection.playlists,
    ];
    final effective = primary.contains(selected) ? selected : primary.first;
    return MobileSegmentedControl<MusicDeckSection>(
      values: primary,
      selected: effective,
      labelBuilder: (section) => section.label(AppLocalizations.of(context)),
      onSelected: onSelected,
    );
  }
}
