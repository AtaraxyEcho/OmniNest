import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_bookshelf_section.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_scaffold.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_parse_feedback.dart';

/// 书架页：已加入书架的条目、正在阅读与阅读报告。
class ReaderBookshelfPage extends ConsumerStatefulWidget {
  const ReaderBookshelfPage({super.key});

  @override
  ConsumerState<ReaderBookshelfPage> createState() =>
      _ReaderBookshelfPageState();
}

class _ReaderBookshelfPageState extends ConsumerState<ReaderBookshelfPage> {
  Set<String> _importingIds = const {};

  void _syncImportingIds(List<ReaderItem> items) {
    _importingIds =
        items.where((item) => item.isParsing).map((item) => item.id).toSet();
  }

  Future<void> _onRefresh() async {
    await ref.read(readerCenterControllerProvider.notifier).refresh();
    ref.invalidate(readerStatsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(readerCenterControllerProvider);
    final state = stateAsync.asData?.value;
    _syncImportingIds(state?.items ?? const []);
    final statsAsync = ref.watch(readerStatsProvider);

    return ReaderPageScaffold(
      target: ReaderPageTarget.bookshelf,
      onRefresh: _onRefresh,
      child: ReaderParseFeedback(
        child: stateAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (data) {
            final shelved = data.bookshelfItems;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ReadingNowCard(
                  book:
                      data.continueItems.isNotEmpty
                          ? data.continueItems.first
                          : null,
                  onTap:
                      data.continueItems.isNotEmpty
                          ? () => _onOpenItem(data.continueItems.first)
                          : null,
                ),
                if (data.continueItems.isNotEmpty) const SizedBox(height: 20),
                BookshelfGrid(
                  books: shelved,
                  onOpenItem: _onOpenItem,
                  onDeleteItem: _onDeleteItem,
                  onCancelImport: _onCancelImport,
                  importingIds: _importingIds,
                ),
                const SizedBox(height: 20),
                ReadingReportCard(stats: statsAsync.asData?.value),
              ],
            );
          },
        ),
      ),
    );
  }

  void _onOpenItem(ReaderItem item) {
    if (item.id.isEmpty) return;
    context.push('/reader/items/${item.id}');
  }

  Future<void> _onDeleteItem(ReaderItem item) async {
    await ref.read(readerCenterControllerProvider.notifier).deleteItem(item.id);
  }

  Future<void> _onCancelImport(ReaderItem item) async {
    await ref
        .read(readerCenterControllerProvider.notifier)
        .cancelImport(item.id);
  }
}
