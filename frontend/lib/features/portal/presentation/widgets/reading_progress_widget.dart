import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_cover_image.dart';

/// 阅读进度卡片 — 展示最近在读书籍的标题与进度
class ReadingProgressWidget extends StatelessWidget {
  const ReadingProgressWidget({this.item, super.key});

  final ReaderItem? item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final current = item;
    // 后端契约里 progressPercent 是 0~1 的比值（reader_progress.progress_percent 有
    // CHECK 约束兜住），这里只做展示换算，不能再除一次 100。
    final progressRatio = (current?.progressPercent ?? 0).clamp(0.0, 1.0);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/reader'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    color: colorScheme.tertiary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(l10n.portalReading, style: theme.textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 12),
              if (current == null)
                Text(
                  l10n.portalNoReadingBook,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 后端封面多为接口路径，必须走 AuthCoverImage 认证加载。
                    AuthCoverImage(
                      itemId: current.id,
                      width: 48,
                      height: 64,
                      borderRadius: BorderRadius.circular(6),
                      fallback: Icon(
                        Icons.menu_book_outlined,
                        size: 22,
                        color: colorScheme.tertiary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            current.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: progressRatio.toDouble(),
                              minHeight: 3,
                              backgroundColor:
                                  colorScheme.surfaceContainerHighest,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${(progressRatio * 100).round()}%',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
