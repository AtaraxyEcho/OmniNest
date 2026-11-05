import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/reader/domain/reader_highlight_palette.dart';

/// 阅读器选区高亮色选点栏：5 个 36dp 热区圆点。
///
/// 新建高亮时点任一色即创建；已有高亮时点其他色原地换色，点当前色取消高亮。
class ReaderHighlightColorBar extends StatelessWidget {
  const ReaderHighlightColorBar({
    required this.selectedColor,
    required this.onSelect,
    super.key,
  });

  final String? selectedColor;
  final ValueChanged<String> onSelect;

  static Color parseColor(String hex) {
    final normalized = hex.replaceFirst('#', '');
    try {
      return Color(int.parse('FF$normalized', radix: 16));
    } on FormatException {
      return Colors.yellow;
    }
  }

  static String labelFor(AppLocalizations l10n, String hex) {
    return switch (hex.toUpperCase()) {
      '#FFEB3B' => l10n.readerHighlightColorYellow,
      '#4CAF50' => l10n.readerHighlightColorGreen,
      '#2196F3' => l10n.readerHighlightColorBlue,
      '#E91E63' => l10n.readerHighlightColorPink,
      '#E0E0E0' => l10n.readerHighlightColorGray,
      _ => l10n.readerHighlightColor,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final colorHex in ReaderHighlightPalette.colors)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Tooltip(
              message: labelFor(l10n, colorHex),
              child: Semantics(
                button: true,
                label: labelFor(l10n, colorHex),
                selected: selectedColor == colorHex,
                child: InkWell(
                  onTap: () => onSelect(colorHex),
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: parseColor(colorHex),
                          border:
                              selectedColor == colorHex
                                  ? Border.all(
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                    width: 2,
                                  )
                                  : null,
                        ),
                        child:
                            selectedColor == colorHex
                                ? const Icon(
                                  Icons.check,
                                  size: 15,
                                  color: Colors.black,
                                )
                                : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
