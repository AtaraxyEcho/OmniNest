import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
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
          MovieRedesignEmptyState(
            icon: Icons.video_collection_rounded,
            title: l10n.videoNoMediaItems,
            subtitle: l10n.videoNewCollection,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 768 ? 3 : (width >= 640 ? 2 : 1);
              final gap = 14.0;
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
                  fontSize: 14,
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
                  fontSize: 14,
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
  final itemsAsync = ref.read(collectionItemsProvider(collection.id));
  await showDialog<void>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          backgroundColor: context.videoColors.surfaceContainerHigh,
          title: Text(collection.name),
          content: SizedBox(
            width: 500,
            height: 400,
            child: itemsAsync.when(
              data:
                  (items) =>
                      items.isEmpty
                          ? Center(
                            child: Text(
                              AppLocalizations.of(context).videoCollectionEmpty,
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
                                      AppLocalizations.of(context).coreDelete,
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () async {
                                    if (!context.mounted) return;
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
                                      if (context.mounted) {
                                        showMovieFeedback(
                                          context,
                                          movieErrorMessage(error),
                                          isError: true,
                                        );
                                      }
                                      return;
                                    }
                                    if (!context.mounted) return;
                                    ref.invalidate(
                                      collectionItemsProvider(collection.id),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error:
                  (e, _) => Center(
                    child: Text(
                      AppLocalizations.of(
                        context,
                      ).videoLoadFailedWith(e.toString()),
                    ),
                  ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppLocalizations.of(context).videoClose),
            ),
          ],
        ),
  );
}
