import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/residual_chrome_colors.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 行内代码相对正文的字号倍率。
const double readerCodeFontScale = 0.9;

/// 行内小标题相对正文的字号倍率。
const double readerHeadingSpanScale = 1.15;

/// 上标/下标相对正文的字号倍率。
const double readerScriptSpanScale = 0.75;

/// 根据 [ReaderInlineSpan] 的样式属性构建 [TextStyle]。
///
/// 供分页引擎与渲染侧复用，确保测量与渲染的样式完全一致。凡是**影响字宽**
/// 的属性（字号、字族）都必须只在这里表达一次：渲染侧另抄一份时，同一块
/// 文本会按一种宽度测量、按另一种宽度折行，行差直接变成页区间与字符偏移
/// 漂移。`ReaderViewContent.spanStyle` 是这里的稳定转发入口。
TextStyle readerSpanStyle(ReaderInlineSpan span, ReaderViewSettings settings) {
  final fontSize =
      span.isCode
          ? settings.fontSize * readerCodeFontScale
          : span.isHeading
          ? settings.fontSize * readerHeadingSpanScale
          : span.isSuperscript || span.isSubscript
          ? settings.fontSize * readerScriptSpanScale
          : settings.fontSize;
  return TextStyle(
    fontFamily:
        span.isCode ? AppTypography.monoFamily : settings.resolvedFontFamily,
    fontFamilyFallback: span.isCode ? AppTypography.monoFamilyFallback : null,
    fontSize: fontSize,
    height: settings.lineHeight,
    // 与 ReaderViewSettings.bodyStyle 同源：稿子 `.article-column > p` 的 .025em。
    letterSpacing: fontSize * ReaderViewSettings.bodyLetterSpacingScale,
    fontWeight: span.isBold ? FontWeight.w700 : FontWeight.w400,
    fontStyle: span.isItalic ? FontStyle.italic : FontStyle.normal,
    color: settings.onSurfaceColor.withValues(alpha: 0.90),
    decoration: TextDecoration.combine([
      if (span.isDeleted) TextDecoration.lineThrough,
      if (span.isUnderlined) TextDecoration.underline,
    ]),
    decorationColor: settings.onSurfaceColor.withValues(alpha: 0.90),
    backgroundColor:
        span.isMarked
            ? ReaderGeneratedCoverColors.highlightTint.withValues(alpha: 0.30)
            : null,
    fontFeatures: [
      if (span.isSuperscript) const FontFeature.superscripts(),
      if (span.isSubscript) const FontFeature.subscripts(),
    ],
  );
}
