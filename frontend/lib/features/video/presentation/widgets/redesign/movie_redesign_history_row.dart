import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';

/// 观看历史行数据：标题、副信息、缩略图与时间文案由调用方组装。
class MovieRedesignHistoryEntry {
  const MovieRedesignHistoryEntry({
    required this.title,
    required this.subtitle,
    required this.timeText,
    required this.progressText,
    this.thumbUrl,
    this.onTap,
    this.onDelete,
  });

  final String title;
  final String subtitle;
  final String timeText;

  /// 进度或完成标记（如 "100%"、"S01E03"）。
  final String progressText;
  final String? thumbUrl;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
}

/// 新版观看历史列表容器 + 行：缩略图 + 标题 + 等宽时间与进度。
class MovieRedesignHistoryList extends StatelessWidget {
  const MovieRedesignHistoryList({required this.entries, super.key});

  final List<MovieRedesignHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: palette.border),
        borderRadius: MovieRedesignPalette.borderRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: palette.border),
            MovieRedesignHistoryRow(entry: entries[i]),
          ],
        ],
      ),
    );
  }
}

class MovieRedesignHistoryRow extends StatefulWidget {
  const MovieRedesignHistoryRow({required this.entry, super.key});

  final MovieRedesignHistoryEntry entry;

  @override
  State<MovieRedesignHistoryRow> createState() =>
      _MovieRedesignHistoryRowState();
}

class _MovieRedesignHistoryRowState extends State<MovieRedesignHistoryRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.movieRedesign;
    final text = context.movieRedesignText;
    final entry = widget.entry;
    final wide = MediaQuery.sizeOf(context).width >= 640;
    return MouseRegion(
      cursor:
          entry.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered ? palette.muted : Colors.transparent,
        child: InkWell(
          onTap: entry.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: MovieRedesignPalette.borderRadius,
                  child: SizedBox(
                    width: wide ? 56 : 48,
                    height: wide ? 40 : 32,
                    child: _HistoryThumb(url: entry.thumbUrl),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.body(
                          size: AppTypography.bodyLarge,
                          weight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.mono(size: AppTypography.bodySmall),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (wide) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        entry.timeText,
                        style: text.mono(size: AppTypography.bodySmall),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.progressText,
                        style: text.mono(
                          size: AppTypography.bodySmall,
                          color: palette.primary,
                        ),
                      ),
                    ],
                  ),
                ] else
                  Text(
                    entry.progressText,
                    style: text.mono(
                      size: AppTypography.bodySmall,
                      color: palette.primary,
                    ),
                  ),
                if (entry.onDelete != null)
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _hovered ? 1 : 0,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: null,
                      onPressed: entry.onDelete,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: palette.mutedForeground,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryThumb extends StatelessWidget {
  const _HistoryThumb({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    if (url == null || url.isEmpty) {
      return ColoredBox(color: context.movieRedesign.muted);
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder:
          (context, error, stackTrace) =>
              ColoredBox(color: context.movieRedesign.muted),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        return ColoredBox(color: context.movieRedesign.muted);
      },
    );
  }
}
