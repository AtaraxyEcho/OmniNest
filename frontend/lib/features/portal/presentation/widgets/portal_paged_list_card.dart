import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/portal/application/portal_paged_cards.dart';

/// Portal 分页列表卡：卡片头点击进入模块，卡体为有界内滚动列表——
/// 首屏一页 10 条，滚到距底约两行时静默追加下一页（无感加载），
/// 数据耗尽即止；追加失败在尾部给重试行，不打断已加载内容。
class PortalPagedListCard<T> extends ConsumerStatefulWidget {
  const PortalPagedListCard({
    required this.provider,
    required this.headerIcon,
    required this.headerTitle,
    required this.openRoute,
    required this.emptyMessage,
    required this.rowBuilder,
    this.visibleHeight = 320,
    super.key,
  });

  final AsyncNotifierProvider<
    PortalPagedListController<T>,
    PortalPagedListState<T>
  >
  provider;

  final IconData headerIcon;
  final String headerTitle;
  final String openRoute;
  final String emptyMessage;
  final Widget Function(T item) rowBuilder;
  final double visibleHeight;

  @override
  ConsumerState<PortalPagedListCard<T>> createState() =>
      _PortalPagedListCardState<T>();
}

class _PortalPagedListCardState<T>
    extends ConsumerState<PortalPagedListCard<T>> {
  final ScrollController _scrollController = ScrollController();

  static const double _loadMoreRemainingExtent = 120;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels <=
        _loadMoreRemainingExtent) {
      final controller = ref.read(widget.provider.notifier);
      unawaited(controller.loadMore());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(widget.provider);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => context.go(widget.openRoute),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: [
                  Icon(
                    widget.headerIcon,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.headerTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          state.when(
            loading:
                () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            error:
                (error, stackTrace) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          describeUserFacingError(error).displayMessage,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(widget.provider),
                        child: Text(l10n.coreRetry),
                      ),
                    ],
                  ),
                ),
            data: (value) {
              if (value.items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                  child: Text(
                    widget.emptyMessage,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              final showFooter = value.hasMore || value.loadingMore;
              return SizedBox(
                height: widget.visibleHeight,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  itemCount: value.items.length + (showFooter ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= value.items.length) {
                      if (value.errorMessage != null) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  value.errorMessage!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed:
                                    () => unawaited(
                                      ref
                                          .read(widget.provider.notifier)
                                          .loadMore(),
                                    ),
                                child: Text(l10n.coreRetry),
                              ),
                            ],
                          ),
                        );
                      }
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    return widget.rowBuilder(value.items[index]);
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
