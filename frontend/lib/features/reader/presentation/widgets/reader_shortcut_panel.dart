import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 阅读器快捷键说明列表。
class ReaderShortcutPanel extends StatelessWidget {
  const ReaderShortcutPanel({
    required this.settings,
    required this.isComic,
    super.key,
  });

  final ReaderViewSettings settings;
  final bool isComic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = <(String, String)>[
      ('Space / PageDown', l10n.readerShortcutTurnPage),
      ('Shift + Space / PageUp', l10n.readerShortcutTurnPage),
      ('T', l10n.readerShortcutContents),
      if (!isComic) ('B', l10n.readerShortcutBookmark),
      if (!isComic) ('Ctrl / Cmd + F', l10n.readerShortcutSearch),
      if (!isComic) ('N', l10n.readerShortcutAnnotations),
      ('F', l10n.readerShortcutImmersive),
      ('F11', l10n.readerShortcutFullscreen),
      if (!isComic) ('+ / - / 0', l10n.readerShortcutTypography),
      if (isComic) ('M', l10n.readerShortcutMode),
      ('Esc', l10n.readerShortcutClose),
      ('?', l10n.readerShortcutsTitle),
    ];

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      separatorBuilder:
          (_, _) => Divider(
            height: 1,
            indent: 20,
            endIndent: 20,
            color: settings.onSurfaceColor.withValues(alpha: 0.07),
          ),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 112),
                child: Text(
                  entry.$1,
                  style: TextStyle(
                    color: settings.accentColor,
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  entry.$2,
                  style: TextStyle(
                    color: settings.onSurfaceColor,
                    fontSize: AppTypography.bodyMedium,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
