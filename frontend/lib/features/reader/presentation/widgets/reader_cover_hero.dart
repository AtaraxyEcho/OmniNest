import 'package:flutter/material.dart';
import 'package:omninest/features/reader/domain/reader_item.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_book_cover.dart';

/// 书架网格与阅读详情页共用的封面共享元素。
///
/// tag 统一走 [tagFor]，避免两处各写一份字符串导致转场静默失效。
///
/// 默认开启，但**只有网格卡片允许开启**：书架首页的「继续阅读」横滑轨与下方
/// 主网格常同屏出现同一本书，两处都用同一个 tag 会直接触发
/// `Multiple heroes that share the same tag` 断言崩溃。
class ReaderCoverHero extends StatelessWidget {
  const ReaderCoverHero({
    required this.itemId,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final String itemId;
  final Widget child;
  final bool enabled;

  static String tagFor(String itemId) => 'reader-cover-$itemId';

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }
    return Hero(tag: tagFor(itemId), child: child);
  }
}

/// 阅读/漫画详情页的 2:3 大封面（参与共享元素转场）。
///
/// 详情页的封面尺寸与圆角只在这里维护：两处详情页各写一份会在改版式时漂移。
class ReaderDetailCoverHero extends StatelessWidget {
  const ReaderDetailCoverHero({required this.item, super.key});

  final ReaderItem item;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: ReaderCoverHero(
        itemId: item.id,
        child: ReaderBookCover(item: item, size: ReaderCoverSize.large),
      ),
    );
  }
}
