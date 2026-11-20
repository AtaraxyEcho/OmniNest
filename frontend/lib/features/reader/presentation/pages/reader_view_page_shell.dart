part of 'reader_view_page.dart';

/// 阅读页路由 Shell（状态类在 reader_view_page.dart 主体）。
class ReaderViewPage extends ConsumerStatefulWidget {
  const ReaderViewPage({
    required this.itemId,
    required this.chapterId,
    this.entry,
    this.initialCharOffset,
    super.key,
  });

  final String itemId;
  final String chapterId;

  /// 路由进入语义（`chapter`=目录显式选章进章首，`offset`=按
  /// [initialCharOffset] 精确定位，其余=续读恢复）。
  final String? entry;

  /// `entry=offset` 时的章内字符偏移（书签等精确定位入口）。
  final int? initialCharOffset;

  @override
  ConsumerState<ReaderViewPage> createState() => _ReaderViewPageState();
}
