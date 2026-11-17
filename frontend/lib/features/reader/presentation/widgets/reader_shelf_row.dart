import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_book_cover.dart';

/// 书架编号列表行：编号 + 小封面 + 标题作者 + 进度/完成 + 内容类型徽标。
class ReaderShelfRow extends StatelessWidget {
  const ReaderShelfRow({
    required this.index,
    required this.item,
    required this.onTap,
    super.key,
  });

  final int index;
  final ReaderItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: rc.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '${index + 1}'.padLeft(2, '0'),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: rc.onSurfaceVariant,
                    fontSize: AppTypography.labelSmall,
                    height: 1.2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 18),
              SizedBox(
                width: 36,
                height: 54,
                child: ReaderBookCover(item: item, size: ReaderCoverSize.row),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: rc.onSurface,
                        fontSize: AppTypography.titleMedium,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.authorName?.isNotEmpty == true
                          ? item.authorName!
                          : item.itemType,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: rc.onSurfaceVariant,
                        fontSize: AppTypography.labelSmall,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _ProgressCell(progress: item.progressPercent),
              const SizedBox(width: 12),
              _KindBadge(label: item.isComic ? 'COMIC' : 'TEXT'),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: rc.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 进度单元：读完✓ / 进行中细线+百分比 / 未读 —。
class _ProgressCell extends StatelessWidget {
  const _ProgressCell({required this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    final p = progress;
    if (p != null && p >= 1) {
      return Icon(Icons.check_rounded, size: 13, color: rc.reading);
    }
    if (p != null && p > 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: 64,
            child: Container(
              height: 1,
              color: rc.outlineVariant,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: p.clamp(0.0, 1.0),
                child: Container(height: 1, color: rc.reading),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(p * 100).round()}%',
            style: TextStyle(
              color: rc.onSurfaceVariant,
              // ignore: font_size_whitelist
              fontSize: 10,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    }
    return Text(
      '—',
      // ignore: font_size_whitelist
      style: TextStyle(color: rc.onSurfaceVariant, fontSize: 10, height: 1),
    );
  }
}

/// 内容类型徽标（TEXT / COMIC）。
class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final rc = context.readerColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: rc.outlineVariant)),
      child: Text(
        label,
        style: TextStyle(
          color: rc.onSurfaceVariant,
          // ignore: font_size_whitelist
          fontSize: 9,
          height: 1.2,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
