import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_empty_state.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_scaffold.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_parse_feedback.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_shelf_row.dart';

/// 书架页：已加入书架的条目编号列表。
class ReaderBookshelfPage extends ConsumerWidget {
  const ReaderBookshelfPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rc = context.readerColors;
    final stateAsync = ref.watch(readerCenterControllerProvider);
    final state = stateAsync.asData?.value;
    final shelved = state?.bookshelfItems ?? const <ReaderItem>[];
    return ReaderPageScaffold(
      target: ReaderPageTarget.bookshelf,
      // 书架自带滚动体：外层若是页级 SingleChildScrollView，列表的
      // builder 惰性会失效（需按内容固有高度全量布局）。
      childOwnScroll: true,
      onRefresh:
          () => ref.read(readerCenterControllerProvider.notifier).refresh(),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                AppLocalizations.of(context).readerNavBookshelf,
                style: TextStyle(
                  color: rc.onSurface,
                  fontSize: MediaQuery.sizeOf(context).width >= 1024 ? 36 : 30,
                  height: 1.15,
                  fontFamily: kReaderSerifFamily,
                  fontStyle: FontStyle.italic,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              Text(
                '${shelved.length}',
                style: TextStyle(
                  color: rc.onSurfaceVariant,
                  fontSize: AppTypography.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: rc.outlineVariant.withValues(alpha: 0.6)),
        ],
      ),
      child: ReaderParseFeedback(
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            if (shelved.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: ReaderEmptyState(
                  title: AppLocalizations.of(context).readerShelfEmpty,
                  subtitle: AppLocalizations.of(context).readerShelfEmptyHint,
                  icon: Icons.auto_stories_outlined,
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  MediaQuery.sizeOf(context).width >= 1024 ? 32 : 24,
                  0,
                  MediaQuery.sizeOf(context).width >= 1024 ? 32 : 24,
                  40,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final item = shelved[index];
                    return Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: rc.outlineVariant.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                      child: ReaderShelfRow(
                        index: index,
                        item: item,
                        onTap: () => context.push('/reader/items/${item.id}'),
                      ),
                    );
                  }, childCount: shelved.length),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
