import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_group.dart';
import 'package:omninest/features/photos/domain/photo_relation.dart';

/// 关联视图每个维度默认展示的实体数量；超出部分聚合并提示。
const int relationEntitiesPerDimension = 12;

/// 关系实体：图谱节点的展示模型。
class RelationEntity {
  const RelationEntity({
    required this.type,
    required this.key,
    required this.label,
    required this.weight,
  });

  final PhotoRelationNodeType type;
  final String key;
  final String label;
  final int weight;

  String get id => '${type.value}:$key';
}

/// 构建指定维度的关系实体列表（按权重排序，可选截断）。
List<RelationEntity> relationEntitiesForDimension({
  required PhotoRelationGraph relation,
  required PhotoRelationNodeType dimension,
  int limit = relationEntitiesPerDimension,
}) {
  final entities =
      relation.nodes
          .where((node) => node.type == dimension)
          .map(
            (node) => RelationEntity(
              type: node.type,
              key: node.key,
              label: node.label ?? node.key,
              weight: node.weight,
            ),
          )
          .toList()
        ..sort((left, right) {
          final byWeight = right.weight.compareTo(left.weight);
          return byWeight != 0 ? byWeight : left.key.compareTo(right.key);
        });
  if (limit <= 0 || entities.length <= limit) {
    return entities;
  }
  return entities.sublist(0, limit);
}

/// 某维度超出展示上限的实体数量。
int relationEntitiesOverflow({
  required PhotoRelationGraph relation,
  required PhotoRelationNodeType dimension,
  int limit = relationEntitiesPerDimension,
}) {
  final total = relation.nodes.where((node) => node.type == dimension).length;
  final overflow = total - limit;
  return overflow > 0 ? overflow : 0;
}

/// 返回边上与指定节点相对的另一端；指定端不在该边上时返回 null。
RelationEntity? edgeOtherEnd(PhotoRelationEdge edge, String selectedId) {
  final sourceId = '${edge.sourceType.value}:${edge.sourceKey}';
  final targetId = '${edge.targetType.value}:${edge.targetKey}';
  if (sourceId == selectedId) {
    return RelationEntity(
      type: edge.targetType,
      key: edge.targetKey,
      label: edge.targetKey,
      weight: edge.weight,
    );
  }
  if (targetId == selectedId) {
    return RelationEntity(
      type: edge.sourceType,
      key: edge.sourceKey,
      label: edge.sourceKey,
      weight: edge.weight,
    );
  }
  return null;
}

/// 找出与选中实体关联的其他实体（按共现强度排序，可选截断）。
List<RelationEntity> relatedEntities({
  required PhotoRelationGraph relation,
  required RelationEntity selected,
  int limit = relationEntitiesPerDimension,
}) {
  final selectedId = selected.id;
  final candidates = <String, RelationEntity>{
    for (final node in relation.nodes)
      if (node.type != PhotoRelationNodeType.person &&
          !(node.type == selected.type && node.key == selected.key))
        '${node.type.value}:${node.key}': RelationEntity(
          type: node.type,
          key: node.key,
          label: node.label ?? node.key,
          weight: node.weight,
        ),
  };
  final connected = <String, RelationEntity>{};
  for (final edge in relation.edges) {
    final other = edgeOtherEnd(edge, selectedId);
    if (other == null) continue;
    final candidate = candidates[other.id];
    if (candidate == null) continue;
    final existing = connected[other.id];
    if (existing == null || existing.weight < candidate.weight) {
      connected[other.id] = candidate;
    }
  }
  final list =
      connected.values.toList()..sort((left, right) {
        final byWeight = right.weight.compareTo(left.weight);
        return byWeight != 0 ? byWeight : left.key.compareTo(right.key);
      });
  if (limit <= 0 || list.length <= limit) {
    return list;
  }
  return list.sublist(0, limit);
}

/// 关联实体照片提供者：按实体 ID 惰性加载（相册走详情，时间/地点走分组）。
final entityPhotosProvider = FutureProvider.autoDispose
    .family<List<PhotoItem>, String>((ref, entityId) async {
      final state = ref.watch(photoCenterControllerProvider).asData?.value;
      if (state == null) return const <PhotoItem>[];
      final relation = state.relationGraph;
      final node = relation.nodes.firstWhere(
        (node) => '${node.type.value}:${node.key}' == entityId,
        orElse:
            () => PhotoRelationNode(
              type: PhotoRelationNodeType.album,
              key: '',
              label: null,
              weight: 0,
            ),
      );
      final controller = ref.read(photoCenterControllerProvider.notifier);
      switch (node.type) {
        case PhotoRelationNodeType.album:
          if (node.key.isEmpty) return const <PhotoItem>[];
          final detail = await ref.read(
            photoAlbumDetailProvider(node.key).future,
          );
          return detail.photos;
        case PhotoRelationNodeType.time:
          await controller.loadGroups(GroupBy.date, force: true);
        case PhotoRelationNodeType.location:
          await controller.loadGroups(GroupBy.location, force: true);
        case PhotoRelationNodeType.person:
          return const <PhotoItem>[];
      }
      final latest = ref.read(photoCenterControllerProvider).asData?.value;
      return latest?.groups
              ?.where((group) => group.groupKey == node.key)
              .expand((group) => group.photos)
              .toList(growable: false) ??
          const <PhotoItem>[];
    });

/// 关联视图：浏览时间、地点与相册实体，并查看实体间的共现关系。
/// 确定性的主从布局，无物理模拟与画布。
class PhotoRelationView extends ConsumerStatefulWidget {
  const PhotoRelationView({super.key});

  @override
  ConsumerState<PhotoRelationView> createState() => _PhotoRelationViewState();
}

class _PhotoRelationViewState extends ConsumerState<PhotoRelationView> {
  RelationEntity? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initialLoad();
    });
  }

  Future<void> _initialLoad() async {
    final controller = ref.read(photoCenterControllerProvider.notifier);
    final current = ref.read(photoCenterControllerProvider).asData?.value;
    if (current != null && current.relationGraph.nodes.isEmpty) {
      await controller.loadRelationGraph();
    }
    if (!mounted) return;
    _ensureSelection();
  }

  void _ensureSelection() {
    final state = ref.read(photoCenterControllerProvider).asData?.value;
    if (state == null || _selected != null) return;
    final relation = state.relationGraph;
    for (final dimension in [
      PhotoRelationNodeType.time,
      PhotoRelationNodeType.location,
      PhotoRelationNodeType.album,
    ]) {
      final entities = relationEntitiesForDimension(
        relation: relation,
        dimension: dimension,
      );
      if (entities.isNotEmpty) {
        setState(() => _selected = entities.first);
        return;
      }
    }
  }

  void _select(RelationEntity entity) {
    setState(() => _selected = entity);
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(photoCenterControllerProvider);
    return stateAsync.when(
      data:
          (state) => _RelationBody(
            state: state,
            selected: _selected,
            onSelect: _select,
          ),
      error:
          (error, stackTrace) => _EmptyHint(
            message: describeUserFacingError(error).displayMessage,
            isLoading: false,
          ),
      loading: () => const _EmptyHint(message: '', isLoading: true),
    );
  }
}

class _RelationBody extends StatelessWidget {
  const _RelationBody({
    required this.state,
    required this.selected,
    required this.onSelect,
  });

  final PhotoCenterState state;
  final RelationEntity? selected;
  final ValueChanged<RelationEntity> onSelect;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1000) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 280,
            child: _DimensionList(
              state: state,
              selected: selected,
              onSelect: onSelect,
            ),
          ),
          VerticalDivider(width: 1, color: context.photosColors.outlineVariant),
          Expanded(
            child: _EntityDetail(
              state: state,
              selected: selected,
              onSelect: onSelect,
            ),
          ),
        ],
      );
    }
    return _CompactRelationBody(
      state: state,
      selected: selected,
      onSelect: onSelect,
    );
  }
}

class _DimensionList extends StatelessWidget {
  const _DimensionList({
    required this.state,
    required this.selected,
    required this.onSelect,
  });

  final PhotoCenterState state;
  final RelationEntity? selected;
  final ValueChanged<RelationEntity> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.photosColors;
    final sections = <(PhotoRelationNodeType, String, IconData)>[
      (
        PhotoRelationNodeType.time,
        l10n.photosGraphKindTime,
        Icons.schedule_rounded,
      ),
      (
        PhotoRelationNodeType.location,
        l10n.photosGraphKindLocation,
        Icons.place_outlined,
      ),
      (
        PhotoRelationNodeType.album,
        l10n.photosGraphKindAlbum,
        Icons.photo_album_outlined,
      ),
    ];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final (type, label, icon) in sections) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
            child: Row(
              children: [
                Icon(icon, size: 15, color: colors.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          for (final entity in relationEntitiesForDimension(
            relation: state.relationGraph,
            dimension: type,
          ))
            _EntityTile(
              entity: entity,
              selected:
                  selected != null &&
                  selected!.type == entity.type &&
                  selected!.key == entity.key,
              onTap: () => onSelect(entity),
            ),
          if (relationEntitiesOverflow(
                relation: state.relationGraph,
                dimension: type,
              ) >
              0)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                l10n.photosRelOthers(
                  relationEntitiesOverflow(
                    relation: state.relationGraph,
                    dimension: type,
                  ),
                ),
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: AppTypography.bodySmall,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _EntityTile extends StatelessWidget {
  const _EntityTile({
    required this.entity,
    required this.selected,
    required this.onTap,
  });

  final RelationEntity entity;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.photosColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color:
            selected
                ? colors.primaryContainer.withValues(alpha: 0.24)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entity.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: AppTypography.bodyMedium,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '${entity.weight}',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: AppTypography.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EntityDetail extends ConsumerWidget {
  const _EntityDetail({
    required this.state,
    required this.selected,
    required this.onSelect,
  });

  final PhotoCenterState state;
  final RelationEntity? selected;
  final ValueChanged<RelationEntity> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.photosColors;
    final l10n = AppLocalizations.of(context);
    if (selected == null) {
      return const _EmptyHint(message: '', isLoading: false);
    }
    final related = relatedEntities(
      relation: state.relationGraph,
      selected: selected!,
    );
    final photosAsync = ref.watch(entityPhotosProvider(selected!.id));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          selected!.label,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: AppTypography.titleLarge,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.photosAlbumPhotoCount(selected!.weight),
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: AppTypography.bodySmall,
          ),
        ),
        if (related.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            l10n.photosRelCooccurTitle,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: AppTypography.bodyMedium,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entity in related)
                ActionChip(
                  label: Text(entity.label),
                  onPressed: () => onSelect(entity),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        photosAsync.when(
          data:
              (photos) =>
                  photos.isEmpty
                      ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Text(
                          l10n.photosNoPhotos,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      )
                      : LayoutBuilder(
                        builder: (context, constraints) {
                          final columns =
                              constraints.maxWidth >= 900
                                  ? 5
                                  : constraints.maxWidth >= 600
                                  ? 4
                                  : 3;
                          return GridView.builder(
                            itemCount: photos.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                  childAspectRatio: 1,
                                ),
                            itemBuilder: (context, index) {
                              final photo = photos[index];
                              return GestureDetector(
                                onTap:
                                    () => context.push('/photos/${photo.id}'),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child:
                                      photo.coverUrl?.isNotEmpty == true
                                          ? Image.network(
                                            photo.coverUrl!,
                                            fit: BoxFit.cover,
                                          )
                                          : ColoredBox(
                                            color:
                                                context
                                                    .photosColors
                                                    .surfaceContainerHighest,
                                            child: Icon(
                                              Icons.photo_outlined,
                                              color:
                                                  context
                                                      .photosColors
                                                      .onSurfaceVariant,
                                            ),
                                          ),
                                ),
                              );
                            },
                          );
                        },
                      ),
          loading:
              () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          error:
              (error, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  describeUserFacingError(error).displayMessage,
                  style: TextStyle(
                    color: colors.danger,
                    fontSize: AppTypography.bodySmall,
                  ),
                ),
              ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _CompactRelationBody extends StatelessWidget {
  const _CompactRelationBody({
    required this.state,
    required this.selected,
    required this.onSelect,
  });

  final PhotoCenterState state;
  final RelationEntity? selected;
  final ValueChanged<RelationEntity> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.photosColors;
    final l10n = AppLocalizations.of(context);
    final dimensions = [
      PhotoRelationNodeType.time,
      PhotoRelationNodeType.location,
      PhotoRelationNodeType.album,
    ];
    final currentDimension =
        selected?.type ??
        (relationEntitiesForDimension(
              relation: state.relationGraph,
              dimension: PhotoRelationNodeType.time,
            ).isNotEmpty
            ? PhotoRelationNodeType.time
            : relationEntitiesForDimension(
              relation: state.relationGraph,
              dimension: PhotoRelationNodeType.location,
            ).isNotEmpty
            ? PhotoRelationNodeType.location
            : PhotoRelationNodeType.album);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<PhotoRelationNodeType>(
          segments: [
            for (final type in dimensions)
              ButtonSegment(
                value: type,
                label: Text(switch (type) {
                  PhotoRelationNodeType.time => l10n.photosGraphKindTime,
                  PhotoRelationNodeType.location =>
                    l10n.photosGraphKindLocation,
                  PhotoRelationNodeType.album => l10n.photosGraphKindAlbum,
                  PhotoRelationNodeType.person => '',
                }),
              ),
          ],
          selected: {currentDimension},
          onSelectionChanged: (selection) {
            final entities = relationEntitiesForDimension(
              relation: state.relationGraph,
              dimension: selection.first,
            );
            if (entities.isNotEmpty) onSelect(entities.first);
          },
        ),
        const SizedBox(height: 12),
        for (final entity in relationEntitiesForDimension(
          relation: state.relationGraph,
          dimension: currentDimension,
        ))
          _EntityTile(
            entity: entity,
            selected:
                selected != null &&
                selected!.type == entity.type &&
                selected!.key == entity.key,
            onTap: () => onSelect(entity),
          ),
        if (relationEntitiesOverflow(
              relation: state.relationGraph,
              dimension: currentDimension,
            ) >
            0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              l10n.photosRelOthers(
                relationEntitiesOverflow(
                  relation: state.relationGraph,
                  dimension: currentDimension,
                ),
              ),
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: AppTypography.bodySmall,
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.message, required this.isLoading});

  final String message;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(child: Text(message, textAlign: TextAlign.center));
  }
}
