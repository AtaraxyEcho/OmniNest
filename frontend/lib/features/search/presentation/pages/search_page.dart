import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_layout_tokens.dart';
import 'package:omninest/app/theme/global_theme_colors.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/features/search/application/search_controller.dart';
import 'package:omninest/features/search/domain/search_result.dart';
import 'package:omninest/features/search/presentation/widgets/search_result_tile.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({this.initialScope = 'all', super.key});

  final String initialScope;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  late _SearchScope _scope;

  @override
  void initState() {
    super.initState();
    _scope = _SearchScope.fromRoute(widget.initialScope);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final colors = context.globalColors;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.mobileColors.pageMask,
      appBar: AppBar(
        backgroundColor: context.mobileColors.surface,
        foregroundColor: context.mobileColors.textPrimary,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/portal');
            }
          },
        ),
        title: Text(
          l10n.searchTitle,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged:
                  (q) => ref.read(searchQueryProvider.notifier).updateQuery(q),
              onSubmitted: (_) => ref.invalidate(searchResultsProvider),
              style: TextStyle(
                color: colors.onSurface,
                fontSize: AppTypography.titleMedium,
              ),
              decoration: InputDecoration(
                hintText: l10n.searchHint,
                hintStyle: TextStyle(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                prefixIcon: Icon(Icons.search_rounded),
                suffixIcon:
                    _controller.text.isNotEmpty
                        ? IconButton(
                          icon: Icon(Icons.clear_rounded),
                          onPressed: () {
                            _controller.clear();
                            ref.read(searchQueryProvider.notifier).clear();
                          },
                        )
                        : null,
                filled: true,
                fillColor: colors.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          _SearchScopeBar(
            selected: _scope,
            onSelected: (scope) => setState(() => _scope = scope),
          ),
          Expanded(
            child: results.when(
              data: (items) {
                final filtered = items
                    .where((item) => _scope.matches(item.type))
                    .toList(growable: false);
                return filtered.isEmpty
                    ? _EmptyState(
                      hasQuery: ref.watch(searchQueryProvider).isNotEmpty,
                    )
                    : _SearchResultsList(items: filtered);
              },
              loading: () => const _SearchLoadingState(),
              error:
                  (_, _) => MobileInlineState(
                    icon: Icons.cloud_off_outlined,
                    message: l10n.searchFailed,
                    actionLabel: l10n.filesRetry,
                    onAction: () => ref.invalidate(searchResultsProvider),
                    error: true,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _SearchScope {
  all,
  files,
  music,
  photos,
  video,
  reader;

  factory _SearchScope.fromRoute(String value) {
    return _SearchScope.values.firstWhere(
      (scope) => scope.name == value,
      orElse: () => _SearchScope.all,
    );
  }

  bool matches(String type) {
    return switch (this) {
      _SearchScope.all => true,
      _SearchScope.files => type == 'file',
      _SearchScope.music => type == 'music',
      _SearchScope.photos => type == 'photo',
      _SearchScope.video => type == 'video',
      _SearchScope.reader => type == 'book',
    };
  }

  String label(AppLocalizations l10n) {
    return switch (this) {
      _SearchScope.all => l10n.searchScopeAll,
      _SearchScope.files => l10n.searchGroupFile,
      _SearchScope.music => l10n.searchGroupMusic,
      _SearchScope.photos => l10n.searchGroupPhoto,
      _SearchScope.video => l10n.searchGroupVideo,
      _SearchScope.reader => l10n.searchGroupBook,
    };
  }
}

class _SearchScopeBar extends StatelessWidget {
  const _SearchScopeBar({required this.selected, required this.onSelected});

  final _SearchScope selected;
  final ValueChanged<_SearchScope> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: _SearchScope.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final scope = _SearchScope.values[index];
          return ChoiceChip(
            selected: selected == scope,
            showCheckmark: false,
            onSelected: (_) => onSelected(scope),
            label: Text(scope.label(l10n)),
          );
        },
      ),
    );
  }
}

class _SearchResultsList extends StatelessWidget {
  const _SearchResultsList({required this.items});

  final List<SearchResult> items;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<SearchResult>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.type, () => []).add(item);
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final type = grouped.keys.elementAt(index);
        final typeItems = grouped[type]!;
        return _SearchGroup(type: type, items: typeItems);
      },
    );
  }
}

class _SearchGroup extends StatelessWidget {
  const _SearchGroup({required this.type, required this.items});

  final String type;
  final List<SearchResult> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            _typeLabel(l10n, type),
            style: TextStyle(
              fontSize: AppTypography.bodyMedium,
              fontWeight: FontWeight.w700,
              color: context.globalColors.onSurfaceVariant,
            ),
          ),
        ),
        for (final item in items) SearchResultTile(result: item),
      ],
    );
  }

  String _typeLabel(AppLocalizations l10n, String type) {
    return switch (type) {
      'file' => l10n.searchGroupFile,
      'book' => l10n.searchGroupBook,
      'video' => l10n.searchGroupVideo,
      'music' => l10n.searchGroupMusic,
      'photo' => l10n.searchGroupPhoto,
      _ => type,
    };
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasQuery});

  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    final colors = context.globalColors;
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasQuery ? Icons.search_off_rounded : Icons.search_rounded,
            size: 32,
            color: colors.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            hasQuery ? l10n.searchEmptyResult : l10n.searchEmptyQuery,
            style: TextStyle(
              fontSize: AppTypography.titleMedium,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchLoadingState extends StatelessWidget {
  const _SearchLoadingState();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 7,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder:
          (context, index) => const MobileSkeletonBlock(
            height: MobileLayoutTokens.listRowHeight,
          ),
    );
  }
}
