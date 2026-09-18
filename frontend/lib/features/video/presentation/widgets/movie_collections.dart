import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';
import 'package:omninest/features/video/presentation/widgets/movie_styles.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_collection_card.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_empty_state.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_section_header.dart';

import 'movie_feedback.dart';
import 'package:omninest/core/errors/error_message.dart';

class CollectionsSection extends ConsumerWidget {
  const CollectionsSection({
    required this.totalCount,
    required this.collections,
    super.key,
  });

  final int totalCount;
  final List<MovieCollection> collections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.movieRedesign;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: MovieRedesignSectionHeader(
                title: l10n.videoSectionCollections,
                subtitleEn: l10n.videoRedesignSubCollections,
                count: collections.isEmpty ? null : collections.length,
                subtitle: l10n.videoCollectionsSubtitle,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showCreateCollectionDialog(context, ref),
                  borderRadius: MovieRedesignPalette.borderRadius,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      '+ ${l10n.videoNewCollection}',
                      style: context.movieRedesignText.mono(
                        size: 12,
                        color: palette.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (collections.isEmpty)
          // 分区 Column 为左对齐布局，空状态需撑满宽度才能与
          // Sliver 分区一样水平居中。
          Center(
            child: MovieRedesignEmptyState(
              icon: Icons.video_collection_rounded,
              title: l10n.videoNoMediaItems,
              subtitle: l10n.videoNewCollection,
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 768 ? 3 : (width >= 640 ? 2 : 1);
              // 原型 gap-3 sm:gap-4。
              final gap = width >= 640 ? 16.0 : 12.0;
              final cardWidth = (width - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final item in collections)
                    SizedBox(
                      width: cardWidth,
                      child: MovieRedesignCollectionCard(
                        data: MovieRedesignCollectionCardData(
                          name: item.name,
                          nameEn: item.description,
                          count: item.itemCount,
                          onTap: () => _showCollectionItems(context, ref, item),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

Future<void> _showCreateCollectionDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final nameController = TextEditingController();
  final descriptionController = TextEditingController();
  final created = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          backgroundColor: context.videoColors.surfaceContainerHigh,
          title: Text(AppLocalizations.of(context).videoNewCollection),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: TextStyle(
                  color: context.videoColors.onSurface,
                  fontSize: AppTypography.bodyLarge,
                ),
                decoration: movieInputDecoration(
                  context,
                  AppLocalizations.of(context).videoCollectionName,
                ),
              ),
              SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                style: TextStyle(
                  color: context.videoColors.onSurface,
                  fontSize: AppTypography.bodyLarge,
                ),
                decoration: movieInputDecoration(
                  context,
                  AppLocalizations.of(context).videoDescription,
                ),
              ),
            ],
          ),
          actions: [
            SizedBox(
              height: 44,
              child: TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(AppLocalizations.of(context).videoCancel),
              ),
            ),
            SizedBox(
              height: 44,
              child: FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(AppLocalizations.of(context).videoCreate),
              ),
            ),
          ],
        ),
  );
  if (created != true || !context.mounted) {
    nameController.dispose();
    descriptionController.dispose();
    return;
  }
  final name = nameController.text.trim();
  final description = descriptionController.text.trim();
  nameController.dispose();
  descriptionController.dispose();
  if (name.isEmpty) {
    showMovieMessage(
      context,
      AppLocalizations.of(context).videoCollectionNameEmpty,
    );
    return;
  }
  await runMovieAction(
    context,
    () => ref
        .read(movieCenterControllerProvider.notifier)
        .createCollection(
          name: name,
          description: description.isEmpty ? null : description,
        ),
    AppLocalizations.of(context).videoCollectionCreated,
  );
}

Future<void> _showCollectionItems(
  BuildContext context,
  WidgetRef ref,
  MovieCollection collection,
) async {
  await showDialog<void>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          backgroundColor: context.videoColors.surfaceContainerHigh,
          title: Text(collection.name),
          content: SizedBox(
            width: 500,
            height: 400,
            // 弹窗内容订阅合集条目数据源：autoDispose 提供器在弹窗存续期间
            // 保活，数据与错误到达时自动重建；一次性 read 快照会永远停留
            // 在加载态。
            child: Consumer(
              builder: (dialogContext, dialogRef, _) {
                final itemsAsync = dialogRef.watch(
                  collectionItemsProvider(collection.id),
                );
                return itemsAsync.when(
                  data:
                      (items) =>
                          items.isEmpty
                              ? Center(
                                child: Text(
                                  AppLocalizations.of(
                                    dialogContext,
                                  ).videoCollectionEmpty,
                                ),
                              )
                              : ListView.builder(
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  return ListTile(
                                    title: Text(item.title),
                                    subtitle: Text(item.year),
                                    trailing: IconButton(
                                      tooltip:
                                          AppLocalizations.of(
                                            dialogContext,
                                          ).coreDelete,
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                      onPressed: () async {
                                        if (!dialogContext.mounted) {
                                          return;
                                        }
                                        try {
                                          await ref
                                              .read(
                                                movieCenterControllerProvider
                                                    .notifier,
                                              )
                                              .removeCollectionItem(
                                                collectionId: collection.id,
                                                videoItemId: item.id,
                                              );
                                        } on Object catch (error) {
                                          if (dialogContext.mounted) {
                                            showMovieFeedback(
                                              dialogContext,
                                              movieErrorMessage(error),
                                              isError: true,
                                            );
                                          }
                                          return;
                                        }
                                        if (!dialogContext.mounted) {
                                          return;
                                        }
                                        dialogRef.invalidate(
                                          collectionItemsProvider(
                                            collection.id,
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error:
                      (e, _) => Center(
                        child: Text(
                          AppLocalizations.of(
                            dialogContext,
                          ).videoLoadFailedWith(e.toString()),
                        ),
                      ),
                );
              },
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed:
                  () => _showMoviePickerDialog(dialogContext, collection),
              icon: const Icon(Icons.add),
              label: Text(
                AppLocalizations.of(dialogContext).videoCollectionAddMovies,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppLocalizations.of(context).videoClose),
            ),
          ],
        ),
  );
}

Future<void> _showMoviePickerDialog(
  BuildContext context,
  MovieCollection collection,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _MoviePickerDialog(collection: collection),
  );
}

/// 合集添加影片选择器：候选为最近更新的电影，支持本地标题过滤；
/// 已在合集中的条目置灰，支持连续添加多个。
class _MoviePickerDialog extends ConsumerStatefulWidget {
  const _MoviePickerDialog({required this.collection});

  final MovieCollection collection;

  @override
  ConsumerState<_MoviePickerDialog> createState() => _MoviePickerDialogState();
}

class _MoviePickerDialogState extends ConsumerState<_MoviePickerDialog> {
  late final Future<List<MovieVideoItem>> _candidates;
  final Set<String> _adding = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _candidates =
        ref.read(movieCenterControllerProvider.notifier).loadMovieCandidates();
  }

  Future<void> _addMovie(MovieVideoItem item) async {
    if (_adding.contains(item.id)) {
      return;
    }
    setState(() => _adding.add(item.id));
    try {
      await ref
          .read(movieCenterControllerProvider.notifier)
          .addCollectionItem(
            collectionId: widget.collection.id,
            videoItemId: item.id,
          );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      showMovieFeedback(context, movieErrorMessage(error), isError: true);
      return;
    } finally {
      if (mounted) {
        setState(() => _adding.remove(item.id));
      }
    }
    if (!mounted) {
      return;
    }
    ref.invalidate(collectionItemsProvider(widget.collection.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final existingIds =
        ref
            .watch(collectionItemsProvider(widget.collection.id))
            .asData
            ?.value
            .map((item) => item.id)
            .toSet() ??
        <String>{};
    return AlertDialog(
      backgroundColor: context.videoColors.surfaceContainerHigh,
      title: Text(l10n.videoCollectionPickerTitle),
      content: SizedBox(
        width: 480,
        height: 480,
        child: Column(
          children: [
            TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.videoCollectionPickerSearchHint,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<MovieVideoItem>>(
                future: _candidates,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        AppLocalizations.of(context).videoLoadFailedWith(
                          describeUserFacingError(snapshot.error!).message,
                        ),
                      ),
                    );
                  }
                  final query = _query.trim().toLowerCase();
                  final movies =
                      snapshot.data
                          ?.where(
                            (item) =>
                                query.isEmpty ||
                                item.title.toLowerCase().contains(query) ||
                                (item.originalTitle ?? '')
                                    .toLowerCase()
                                    .contains(query),
                          )
                          .toList() ??
                      const <MovieVideoItem>[];
                  if (movies.isEmpty) {
                    return Center(child: Text(l10n.videoCollectionPickerEmpty));
                  }
                  return ListView.builder(
                    itemCount: movies.length,
                    itemBuilder: (context, index) {
                      final item = movies[index];
                      final added = existingIds.contains(item.id);
                      final busy = _adding.contains(item.id);
                      return ListTile(
                        title: Text(item.title),
                        subtitle: Text(item.year),
                        trailing:
                            added
                                ? Tooltip(
                                  message: l10n.videoCollectionAlreadyAdded,
                                  child: const Icon(Icons.check),
                                )
                                : busy
                                ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.add_circle_outline),
                        onTap:
                            added || busy
                                ? null
                                : () => unawaited(_addMovie(item)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.videoClose),
        ),
      ],
    );
  }
}
