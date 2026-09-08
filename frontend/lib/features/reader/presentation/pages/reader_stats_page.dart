import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_bookshelf_section.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_scaffold.dart';

/// 统计页：阅读报告与活动概览。
///
/// 14 天活动柱状图与书库构成为批次 D 内容，数据来自统计聚合接口。
class ReaderStatsPage extends ConsumerWidget {
  const ReaderStatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(readerStatsProvider);
    return ReaderPageScaffold(
      target: ReaderPageTarget.stats,
      onRefresh: () async {
        ref.invalidate(readerStatsProvider);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          statsAsync.when(
            loading:
                () => const SizedBox(
                  height: 120,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
            error: (_, _) => const SizedBox.shrink(),
            data: (stats) => ReadingReportCard(stats: stats),
          ),
        ],
      ),
    );
  }
}
