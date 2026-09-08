import 'package:flutter/material.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_cover_image.dart';

/// 阅读条目封面：真实封面优先，无封面时按条目标题生成纸感配色封面。
///
/// 生成封面参考编辑风设计：深色底 + 左侧书脊线 + 顶部“文/漫”字标 + 衬线标题。
enum ReaderCoverSize { grid, small, row, large }

class ReaderBookCover extends StatelessWidget {
  const ReaderBookCover({required this.item, required this.size, super.key});

  final ReaderItem item;
  final ReaderCoverSize size;

  /// 生成封面配色对（底色, 强调色），按标题哈希稳定选择。
  static const List<(Color, Color)> _palettes = [
    (Color(0xFF2C1A0E), Color(0xFF8B4513)),
    (Color(0xFF0F1E2E), Color(0xFF2A4A6E)),
    (Color(0xFF2A1E0A), Color(0xFF7A5A1A)),
    (Color(0xFF1C2E1C), Color(0xFF3A5A3A)),
    (Color(0xFF1A1A2C), Color(0xFF3A3A6E)),
  ];

  static const Color _coverText = Color(0xFFEEEDE9);

  bool get _showTitle => size != ReaderCoverSize.row;

  bool get _showAuthor =>
      size == ReaderCoverSize.grid || size == ReaderCoverSize.large;

  @override
  Widget build(BuildContext context) {
    final palette = _palettes[item.title.hashCode.abs() % _palettes.length];
    final background = palette.$1;
    final accent = palette.$2;
    final isLarge = size == ReaderCoverSize.large;
    return DecoratedBox(
      decoration: BoxDecoration(color: background),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item.hasCover)
            AuthCoverImage(
              itemId: item.id,
              fit: BoxFit.cover,
              fallback: const SizedBox.shrink(),
            ),
          // 左侧书脊线
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.55)),
            ),
          ),
          // 顶部“文/漫”字标带
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                size == ReaderCoverSize.row ? 6 : 8,
                size == ReaderCoverSize.row ? 3 : 7,
                6,
                size == ReaderCoverSize.row ? 3 : 5,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: accent.withValues(alpha: 0.35)),
                ),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                item.isComic ? '漫' : '文',
                style: TextStyle(
                  color: _coverText.withValues(alpha: 0.55),
                  fontSize: size == ReaderCoverSize.row ? 7 : 8,
                  height: 1,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          // 底部标题与作者
          if (_showTitle)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  size == ReaderCoverSize.row ? 6 : 8,
                  2,
                  6,
                  size == ReaderCoverSize.row ? 4 : 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isLarge)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        height: 1,
                        color: _coverText.withValues(alpha: 0.2),
                      ),
                    Text(
                      item.title,
                      maxLines: size == ReaderCoverSize.row ? 1 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _coverText,
                        fontSize: coverTitleFontSize,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_showAuthor && item.authorName?.isNotEmpty == true) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.authorName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _coverText.withValues(alpha: 0.6),
                          fontSize: coverAuthorFontSize,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  double get coverTitleFontSize => switch (size) {
    ReaderCoverSize.large => 14,
    ReaderCoverSize.grid => 10,
    ReaderCoverSize.small => 9,
    ReaderCoverSize.row => 8,
  };

  double get coverAuthorFontSize => size == ReaderCoverSize.large ? 11 : 8;
}
