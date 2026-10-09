import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_cover_image.dart';

/// 样例 Reader 空间（App.tsx Reader → shelf 视图）的 1:1 内容组件。
///
/// 四段结构：reader-continue 续读特写（纸封 + 拷贝）→ reading-insight
/// 本周洞察（常驻）→ YOUR SHELVES / Read next 书轨 → RECENT NOTES
/// 引用列表。7-10px 微型字号为样例签名密度，逐处登记豁免。
class ReaderSpaceContent extends StatelessWidget {
  const ReaderSpaceContent({
    required this.featureItem,
    required this.railItems,
    required this.notes,
    required this.bookTitles,
    required this.insightMinutes,
    required this.insightChapters,
    this.insightStreakDays,
    required this.onResume,
    required this.onOpenItem,
    required this.onOpenBookshelf,
    this.onOpenStats,
    super.key,
  });

  /// 特写条目：优先续读，库内无续读时退让到最近条目。
  final ReaderItem? featureItem;

  /// 书轨条目（已排除特写条目）。
  final List<ReaderItem> railItems;

  /// 最近笔记（跨书标注）。
  final List<ReaderSpaceNote> notes;

  /// itemId → 书名映射（笔记行副文案用）。
  final Map<String, String> bookTitles;

  /// 本周专注分钟数；null 视为 0（洞察条按样例常驻）。
  final int? insightMinutes;

  /// 本周读完章节数。
  final int insightChapters;

  /// 连续阅读天数；null/0 不展示。
  final int? insightStreakDays;

  /// 特写续读动作（直接进入阅读器）。
  final ValueChanged<ReaderItem> onResume;

  /// 书轨/笔记条目打开动作（进入详情）。
  final ValueChanged<ReaderItem> onOpenItem;

  /// 「书架」动作。
  final VoidCallback onOpenBookshelf;

  /// 洞察条点击进入阅读统计页。
  final VoidCallback? onOpenStats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (featureItem != null)
          _ContinueFeature(item: featureItem!, onResume: onResume),
        _InsightStrip(
          minutes: insightMinutes ?? 0,
          chapters: insightChapters,
          streakDays: insightStreakDays,
          onOpenStats: onOpenStats,
        ),
        if (railItems.isNotEmpty) ...[
          _SpaceSectionHeader(
            eyebrow: AppLocalizations.of(context).readerReadNextEyebrow,
            title: AppLocalizations.of(context).readerReadNextTitle,
            actionLabel: AppLocalizations.of(context).readerNavBookshelf,
            onAction: onOpenBookshelf,
          ),
          _BookRail(items: railItems, onOpenItem: onOpenItem),
        ],
        if (notes.isNotEmpty) ...[
          _SpaceSectionHeader(
            eyebrow: AppLocalizations.of(context).readerNotesEyebrow,
            title: AppLocalizations.of(context).readerNotesTitle,
          ),
          _NotesList(notes: notes, bookTitles: bookTitles),
        ],
      ],
    );
  }
}

/// 最近笔记条目：跨书标注的引用文本 + 书名/日期副文案。
class ReaderSpaceNote {
  const ReaderSpaceNote({
    required this.annotationId,
    required this.itemId,
    required this.quote,
    this.createdAt,
  });

  final String annotationId;
  final String itemId;

  /// 引用文本（优先高亮原文，其次笔记内容）。
  final String quote;
  final DateTime? createdAt;
}

/// 小节标题（样例 section-title）：眉标 + 标题行 + 可选文字动作。
class _SpaceSectionHeader extends StatelessWidget {
  const _SpaceSectionHeader({
    required this.eyebrow,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String eyebrow;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.env.white43,
              // ignore: font_size_whitelist
              fontSize: 9,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.env.ink,
                    fontSize: AppTypography.titleLarge + 1,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                    height: 1.15,
                  ),
                ),
              ),
              if (actionLabel != null && onAction != null)
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: context.env.white70,
                    minimumSize: const Size(48, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(
                      fontSize: AppTypography.labelSmall,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(actionLabel!),
                      const SizedBox(width: 1),
                      OmniIcon(
                        icon: OmniIcons.chevron,
                        size: 16,
                        color: context.env.white70,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 续读特写（样例 reader-continue）：纸封 + 拷贝列，gap 21 垂直居中。
class _ContinueFeature extends StatelessWidget {
  const _ContinueFeature({required this.item, required this.onResume});

  final ReaderItem item;
  final ValueChanged<ReaderItem> onResume;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fraction = (item.progressPercent ?? 0).clamp(0.0, 1.0);
    final hasProgress =
        item.progressPercent != null && item.progressPercent! > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 19, 0, 27),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _FeatureCover(item: item),
          const SizedBox(width: 21),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.readerSpaceContinueEyebrow.toUpperCase(),
                  style: TextStyle(
                    color: context.env.accentInk,
                    // ignore: font_size_whitelist
                    fontSize: 8,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.env.ink,
                    fontFamily: AppTypography.serifFamily,
                    fontFamilyFallback: AppTypography.serifFamilyFallback,
                    // ignore: font_size_whitelist
                    fontSize: 29,
                    height: 1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.authorName?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      item.authorName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.env.inkMuted,
                        fontSize: AppTypography.bodySmall - 1,
                        height: 1.3,
                      ),
                    ),
                  ),
                if (hasProgress)
                  Padding(
                    padding: const EdgeInsets.only(top: 18, bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: fraction,
                              minHeight: 3,
                              color: context.env.accentInk,
                              backgroundColor: context.env.line15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(fraction * 100).round()}%',
                          style: TextStyle(
                            color: context.env.inkMuted,
                            // ignore: font_size_whitelist
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () => onResume(item),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.env.ink,
                    backgroundColor: context.env.line09,
                    side: BorderSide(color: context.env.line13),
                    minimumSize: const Size.fromHeight(45),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(
                      fontSize: AppTypography.labelSmall,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: OmniIcon(
                    icon: OmniIcons.arrow,
                    size: 18,
                    color: context.env.ink,
                  ),
                  label: Text(l10n.readerContinueChapter),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 特写书封：真实封面优先；无封面回退样例纸封（衬线书名 + 作者行）。
class _FeatureCover extends StatelessWidget {
  const _FeatureCover({required this.item});

  final ReaderItem item;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(3),
          right: Radius.circular(14),
        ),
        boxShadow: [
          BoxShadow(color: context.env.readerCoverSpine, offset: Offset(-5, 0)),
          BoxShadow(
            color: Colors.black45,
            blurRadius: 35,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(3),
          right: Radius.circular(14),
        ),
        child: SizedBox(
          width: 132,
          height: 190,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (item.hasCover)
                AuthCoverImage(
                  itemId: item.id,
                  fit: BoxFit.cover,
                  fallback: _PaperCover(
                    title: item.title,
                    author: item.authorName,
                  ),
                )
              else
                _PaperCover(title: item.title, author: item.authorName),
            ],
          ),
        ),
      ),
    );
  }
}

/// 样例纸封：#d5ccad 底、20px 衬线书名居上、8px 作者行沉底。
class _PaperCover extends StatelessWidget {
  const _PaperCover({required this.title, this.author});

  final String title;
  final String? author;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.env.readerCoverBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.env.readerCoverFg,
                fontFamily: AppTypography.serifFamily,
                fontFamilyFallback: AppTypography.serifFamilyFallback,
                // ignore: font_size_whitelist
                fontSize: 20,
                height: 1.05,
              ),
            ),
            const Spacer(),
            if (author?.isNotEmpty == true)
              Text(
                '— $author',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.env.readerCoverFg,
                  // ignore: font_size_whitelist
                  fontSize: 8,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 本周洞察（样例 reading-insight）：上下发丝线 + sparkle 强调图标，
/// 样例中该条常驻，数据缺失时按 0 值呈现。
class _InsightStrip extends StatelessWidget {
  const _InsightStrip({
    required this.minutes,
    required this.chapters,
    this.streakDays,
    this.onOpenStats,
  });

  final int minutes;
  final int chapters;
  final int? streakDays;

  /// 点击整条进入阅读统计页；null 时不可点。
  final VoidCallback? onOpenStats;

  String _formatDuration(int totalMinutes) {
    final hours = totalMinutes ~/ 60;
    final rest = totalMinutes % 60;
    if (hours <= 0) {
      return '$rest';
    }
    return '$hours:${rest.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detail = [
      l10n.readerInsightChapters(chapters),
      if (streakDays != null && streakDays! > 0)
        l10n.readerInsightStreak(streakDays!),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: context.env.line13),
            bottom: BorderSide(color: context.env.line13),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpenStats,
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  OmniIcon(
                    icon: OmniIcons.sparkle,
                    size: 20,
                    color: context.env.accentInk,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.readerSpaceInsightEyebrow.toUpperCase(),
                          style: TextStyle(
                            color: context.env.inkMuted,
                            // ignore: font_size_whitelist
                            fontSize: 8,
                            letterSpacing: 1.3,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.readerInsightFocus(_formatDuration(minutes)),
                          style: TextStyle(
                            color: context.env.ink,
                            fontFamily: AppTypography.serifFamily,
                            fontFamilyFallback:
                                AppTypography.serifFamilyFallback,
                            // ignore: font_size_whitelist
                            fontSize: 21,
                            height: 1.1,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.env.inkMuted,
                            // ignore: font_size_whitelist
                            fontSize: 10,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 书轨（样例 book-rail）：116px 纸封横滑轨。
class _BookRail extends StatelessWidget {
  const _BookRail({required this.items, required this.onOpenItem});

  final List<ReaderItem> items;
  final ValueChanged<ReaderItem> onOpenItem;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 205,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 13),
        itemBuilder: (context, index) {
          final item = items[index];
          return MobilePressable(
            semanticLabel: item.title,
            onTap: () => onOpenItem(item),
            child: SizedBox(
              width: 116,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RailCover(item: item),
                  const SizedBox(height: 9),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.env.ink,
                      fontSize: AppTypography.bodySmall,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.authorName?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        item.authorName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.env.inkMuted,
                          // ignore: font_size_whitelist
                          fontSize: 9,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 书轨封面：真实封面优先，回退「衬线首字母纸封」（样例三色轮换）。
class _RailCover extends StatelessWidget {
  const _RailCover({required this.item});

  final ReaderItem item;

  static const List<(Color, Color)> _paperPalette = [
    (Color(0xFFC9B97F), Color(0xFF2B2924)),
    (Color(0xFF8F988D), Color(0xFF161C19)),
    (Color(0xFFC4AEA2), Color(0xFF2B2924)),
  ];

  @override
  Widget build(BuildContext context) {
    final letter =
        item.title.isNotEmpty ? item.title.characters.first.toUpperCase() : '?';
    final palette = _paperPalette[letter.hashCode.abs() % _paperPalette.length];
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(2),
          right: Radius.circular(10),
        ),
        // polarity-stable：封面书脊高光落在纸色封面上，两极性同值
        boxShadow: [BoxShadow(color: Color(0x29FFFFFF), offset: Offset(-4, 0))],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(2),
          right: Radius.circular(10),
        ),
        child: SizedBox(
          width: 116,
          height: 157,
          child:
              item.hasCover
                  ? AuthCoverImage(
                    itemId: item.id,
                    fit: BoxFit.cover,
                    fallback: _paper(letter, palette),
                  )
                  : _paper(letter, palette),
        ),
      ),
    );
  }

  Widget _paper(String letter, (Color, Color) palette) {
    return ColoredBox(
      color: palette.$1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              letter,
              style: TextStyle(
                color: palette.$2,
                fontFamily: AppTypography.serifFamily,
                fontFamilyFallback: AppTypography.serifFamilyFallback,
                fontSize: AppTypography.displaySmall - 2,
                height: 1,
              ),
            ),
            const Spacer(),
            Text(
              item.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.$2,
                fontFamily: AppTypography.serifFamily,
                fontFamilyFallback: AppTypography.serifFamilyFallback,
                // ignore: font_size_whitelist
                fontSize: 13,
                height: 1.05,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 最近笔记列表（样例 reader-list）：衬线引用 + 书名/日期副文案 + chevron。
class _NotesList extends StatelessWidget {
  const _NotesList({required this.notes, required this.bookTitles});

  final List<ReaderSpaceNote> notes;
  final Map<String, String> bookTitles;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final note in notes)
          MobilePressable(
            semanticLabel: note.quote,
            onTap: () {
              if (note.itemId.isNotEmpty) {
                context.push('/reader/items/${note.itemId}');
              }
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 72),
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: context.env.line13)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '"${note.quote}"',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.env.ink,
                            fontFamily: AppTypography.serifFamily,
                            fontFamilyFallback:
                                AppTypography.serifFamilyFallback,
                            fontSize: AppTypography.titleSmall + 1,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _secondary(note, localizations),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.env.inkMuted,
                            // ignore: font_size_whitelist
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OmniIcon(
                    icon: OmniIcons.chevron,
                    size: 18,
                    color: context.env.inkMuted,
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  String _secondary(ReaderSpaceNote note, MaterialLocalizations localizations) {
    final title = bookTitles[note.itemId] ?? '';
    final date =
        note.createdAt == null
            ? ''
            : localizations.formatShortDate(note.createdAt!);
    return [if (title.isNotEmpty) title, if (date.isNotEmpty) date].join(' · ');
  }
}
