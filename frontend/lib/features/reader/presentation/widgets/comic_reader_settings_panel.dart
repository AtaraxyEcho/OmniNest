import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/features/reader/domain/comic_reader_display_settings.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 漫画阅读器的显示设置面板。
class ComicReaderSettingsPanel extends StatelessWidget {
  const ComicReaderSettingsPanel({
    required this.displaySettings,
    required this.themeSettings,
    required this.onChanged,
    super.key,
  });

  final ComicReaderDisplaySettings displaySettings;
  final ReaderViewSettings themeSettings;
  final ValueChanged<ComicReaderDisplaySettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        _SectionLabel(
          label: l10n.readerReadingMode,
          color: themeSettings.onSurfaceVariantColor,
        ),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: 'page',
              icon: const Icon(Icons.chrome_reader_mode_outlined),
              label: Text(l10n.readerComicModePage),
            ),
            ButtonSegment(
              value: 'scroll',
              icon: const Icon(Icons.view_stream_outlined),
              label: Text(l10n.readerComicModeScroll),
            ),
          ],
          selected: {displaySettings.readingMode},
          onSelectionChanged:
              (selection) => onChanged(
                displaySettings.copyWith(readingMode: selection.first),
              ),
        ),
        const SizedBox(height: 24),
        SwitchListTile(
          value: displaySettings.fullWidth,
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.readerComicFullWidth,
            style: TextStyle(color: themeSettings.onSurfaceColor),
          ),
          subtitle: Text(
            l10n.readerComicFullWidthHint,
            style: TextStyle(color: themeSettings.onSurfaceVariantColor),
          ),
          onChanged:
              (value) => onChanged(displaySettings.copyWith(fullWidth: value)),
        ),
        if (!displaySettings.fullWidth) ...[
          const SizedBox(height: 18),
          _SectionLabel(
            label: l10n.readerComicContentWidth(
              displaySettings.contentWidth.round(),
            ),
            color: themeSettings.onSurfaceVariantColor,
          ),
          AppSlider(
            value: displaySettings.contentWidth,
            min: 480,
            max: 1440,
            divisions: 12,
            onChanged:
                (value) =>
                    onChanged(displaySettings.copyWith(contentWidth: value)),
          ),
        ],
        const SizedBox(height: 18),
        _SectionLabel(
          label: l10n.readerComicPageGap(displaySettings.pageGap.round()),
          color: themeSettings.onSurfaceVariantColor,
        ),
        AppSlider(
          value: displaySettings.pageGap,
          min: 0,
          max: 24,
          divisions: 12,
          onChanged:
              (value) => onChanged(displaySettings.copyWith(pageGap: value)),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: AppTypography.bodyMedium,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
