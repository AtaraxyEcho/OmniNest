import 'package:omninest/app/l10n/app_localizations.dart';

/// 阅读模块展示层本地化辅助函数。
///
/// 将 domain 层模型中的类型标识映射为用户可见的本地化字符串。

/// 将 itemType 映射到本地化标签。
String readerTypeLabel(AppLocalizations l10n, String itemType) {
  return switch (itemType.toUpperCase()) {
    'EPUB' => 'EPUB',
    'TXT' => 'TXT',
    'CBZ' => 'CBZ',
    'ZIP' => 'ZIP',
    'PDF' => 'PDF',
    _ => itemType.toUpperCase(),
  };
}

/// 格式化阅读进度百分比的本地化显示。
String readerProgressLabelText(AppLocalizations l10n, double progressPercent) {
  if (progressPercent <= 0) return l10n.readerNotStarted;
  return '${progressPercent.toStringAsFixed(progressPercent >= 10 ? 0 : 1)}%';
}

/// 格式化章节编号的本地化显示。
String readerChapterLabelText(AppLocalizations l10n, double chapterNumber) {
  if (chapterNumber == chapterNumber.roundToDouble()) {
    return l10n.readerChapterNumber('${chapterNumber.toInt()}');
  }
  return l10n.readerChapterNumber(chapterNumber.toStringAsFixed(1));
}
