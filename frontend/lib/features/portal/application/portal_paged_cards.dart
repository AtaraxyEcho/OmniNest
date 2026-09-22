import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/session/session_epoch.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/photos/application/photo_repository_providers.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/domain/reader_item.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_models.dart';

/// Portal 列表卡分页状态：已加载条目、总数与追加加载在飞标记。
class PortalPagedListState<T> {
  PortalPagedListState({
    List<T>? items,
    this.totalElements = 0,
    this.loadingMore = false,
    this.errorMessage,
  }) : items = items ?? List<T>.empty(growable: false);

  final List<T> items;
  final int totalElements;
  final bool loadingMore;
  final String? errorMessage;

  bool get hasMore => items.length < totalElements;

  PortalPagedListState<T> copyWith({
    List<T>? items,
    int? totalElements,
    bool? loadingMore,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PortalPagedListState<T>(
      items: items ?? this.items,
      totalElements: totalElements ?? this.totalElements,
      loadingMore: loadingMore ?? this.loadingMore,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// 单页取数结果。
class PortalPagedPage<T> {
  const PortalPagedPage({required this.items, required this.totalElements});

  final List<T> items;
  final int totalElements;
}

/// Portal 分页列表卡基类：首屏一页（10 条）；loadMore 以整页游标追加
/// 并按键去重；refresh 按已加载量对齐重拉第一页，列表长度不回跳。
abstract class PortalPagedListController<T>
    extends AsyncNotifier<PortalPagedListState<T>> {
  static const int pageSize = 10;

  Future<PortalPagedPage<T>> fetchPage(int page, int size);

  String itemKey(T item);

  @override
  Future<PortalPagedListState<T>> build() async {
    ref.watch(sessionEpochProvider);
    final page = await fetchPage(0, pageSize);
    return PortalPagedListState<T>(
      items: page.items,
      totalElements: page.totalElements,
    );
  }

  /// 追加加载下一页；翻页游标按整页对齐，避免去重后页码漂移。
  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || current.loadingMore || !current.hasMore) {
      return;
    }
    state = AsyncData(current.copyWith(loadingMore: true, clearError: true));
    final nextPage = current.items.length ~/ pageSize;
    try {
      final page = await fetchPage(nextPage, pageSize);
      if (!ref.mounted) {
        return;
      }
      final latest = state.asData?.value;
      if (latest == null || !latest.loadingMore) {
        return;
      }
      final knownKeys = latest.items.map(itemKey).toSet();
      final fresh = page.items
          .where((item) => knownKeys.add(itemKey(item)))
          .toList(growable: false);
      state = AsyncData(
        latest.copyWith(
          items: <T>[...latest.items, ...fresh],
          totalElements: page.totalElements,
          loadingMore: false,
        ),
      );
    } on Exception catch (error) {
      if (!ref.mounted) {
        return;
      }
      final latest = state.asData?.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(
            loadingMore: false,
            errorMessage: describeUserFacingError(error).message,
          ),
        );
      }
    }
  }

  /// 重进门户与实时脏事件触发的保数据刷新：按已加载量取第一页，
  /// 失败保留旧数据不打断页面。
  Future<void> refresh() async {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    final size =
        current.items.isEmpty
            ? pageSize
            : (current.items.length / pageSize).ceil() * pageSize;
    try {
      final page = await fetchPage(0, size);
      if (!ref.mounted) {
        return;
      }
      state = AsyncData(
        PortalPagedListState<T>(
          items: page.items,
          totalElements: page.totalElements,
        ),
      );
    } on Exception {
      return;
    }
  }
}

/// 影视继续观看卡：接口一次性返回完整列表，此处按页分窗增量呈现
/// （请求不增量，条目呈现增量）。刷新前清缓存以重取服务端最新列表。
class PortalContinueWatchingController
    extends PortalPagedListController<MovieContinueWatching> {
  List<MovieContinueWatching>? _fullList;

  @override
  String itemKey(MovieContinueWatching item) => item.id;

  @override
  Future<void> refresh() async {
    _fullList = null;
    await super.refresh();
  }

  @override
  Future<PortalPagedPage<MovieContinueWatching>> fetchPage(
    int page,
    int size,
  ) async {
    final full =
        _fullList ??= await ref.read(movieApiProvider).continueWatching();
    final start = (page * size).clamp(0, full.length);
    final end = (start + size).clamp(0, full.length);
    return PortalPagedPage(
      items: full.sublist(start, end),
      totalElements: full.length,
    );
  }
}

/// 最近照片卡：消费照片时间线既有分页接口，服务端真分页。
class PortalRecentPhotosController
    extends PortalPagedListController<PhotoItem> {
  @override
  String itemKey(PhotoItem item) => item.id;

  @override
  Future<PortalPagedPage<PhotoItem>> fetchPage(int page, int size) async {
    final result = await ref
        .read(photoApiProvider)
        .listPhotos(page: page, size: size);
    return PortalPagedPage(
      items: result.items,
      totalElements: result.totalElements,
    );
  }
}

final portalContinueWatchingProvider = AsyncNotifierProvider<
  PortalContinueWatchingController,
  PortalPagedListState<MovieContinueWatching>
>(PortalContinueWatchingController.new);

final portalRecentPhotosProvider = AsyncNotifierProvider<
  PortalRecentPhotosController,
  PortalPagedListState<PhotoItem>
>(PortalRecentPhotosController.new);

/// Portal 播放队列卡：队列完整保存在音乐中心状态中，按页分窗呈现
/// （纯呈现分页，不产生网络请求）；每次取数实时重读中心队列，
/// refresh 天然取到最新内容。
class PortalPlaybackQueueController
    extends PortalPagedListController<MusicPlayableItem> {
  @override
  String itemKey(MusicPlayableItem item) => item.playableKey;

  @override
  Future<PortalPagedPage<MusicPlayableItem>> fetchPage(
    int page,
    int size,
  ) async {
    final queue =
        ref.read(musicCenterControllerProvider).asData?.value.playbackItems ??
        const <MusicPlayableItem>[];
    final start = (page * size).clamp(0, queue.length);
    final end = (start + size).clamp(0, queue.length);
    return PortalPagedPage(
      items: queue.sublist(start, end),
      totalElements: queue.length,
    );
  }
}

final portalPlaybackQueueProvider = AsyncNotifierProvider<
  PortalPlaybackQueueController,
  PortalPagedListState<MusicPlayableItem>
>(PortalPlaybackQueueController.new);

/// Portal 书架浏览卡：书库列表接口一次性返回全部条目，此处按页分窗
/// 增量呈现；refresh 清缓存后重取，跨端导入的新书即时可见。
class PortalReaderShelfController
    extends PortalPagedListController<ReaderItem> {
  List<ReaderItem>? _fullList;

  @override
  String itemKey(ReaderItem item) => item.id;

  @override
  Future<void> refresh() async {
    _fullList = null;
    await super.refresh();
  }

  @override
  Future<PortalPagedPage<ReaderItem>> fetchPage(int page, int size) async {
    final full = _fullList ??= await ref.read(readerApiProvider).items();
    final start = (page * size).clamp(0, full.length);
    final end = (start + size).clamp(0, full.length);
    return PortalPagedPage(
      items: full.sublist(start, end),
      totalElements: full.length,
    );
  }
}

final portalReaderShelfProvider = AsyncNotifierProvider<
  PortalReaderShelfController,
  PortalPagedListState<ReaderItem>
>(PortalReaderShelfController.new);

/// Portal 影视浏览项：继续观看条目带进度，最近添加条目带年份等次要文案。
class PortalVideoPreviewItem {
  const PortalVideoPreviewItem({
    required this.id,
    required this.title,
    required this.route,
    this.posterUrl,
    this.progressPercent,
    this.secondaryText,
  });

  final String id;
  final String title;
  final String route;
  final String? posterUrl;

  /// 续播进度（0-100）；非续播项为 null。
  final double? progressPercent;

  /// 最近添加的年份等次要文案。
  final String? secondaryText;

  bool get isContinueWatching => progressPercent != null;
}

/// Portal 影视浏览卡：继续观看在前、最近添加按作品去重补齐，两个来源
/// 均为一次性列表，客户端拼接后分窗增量呈现。
class PortalVideoPreviewController
    extends PortalPagedListController<PortalVideoPreviewItem> {
  List<PortalVideoPreviewItem>? _merged;

  @override
  String itemKey(PortalVideoPreviewItem item) => item.id;

  @override
  Future<void> refresh() async {
    _merged = null;
    await super.refresh();
  }

  @override
  Future<PortalPagedPage<PortalVideoPreviewItem>> fetchPage(
    int page,
    int size,
  ) async {
    final merged = _merged ??= await _loadMerged();
    final start = (page * size).clamp(0, merged.length);
    final end = (start + size).clamp(0, merged.length);
    return PortalPagedPage(
      items: merged.sublist(start, end),
      totalElements: merged.length,
    );
  }

  Future<List<PortalVideoPreviewItem>> _loadMerged() async {
    final api = ref.read(movieApiProvider);
    final continueItems = await api.continueWatching();
    final recent = await api.recent();
    final seen = <String>{};
    final items = <PortalVideoPreviewItem>[];
    for (final watching in continueItems) {
      if (!seen.add(watching.id)) {
        continue;
      }
      items.add(
        PortalVideoPreviewItem(
          id: watching.id,
          title: watching.title,
          route: '/video/${watching.id}/play',
          posterUrl: watching.posterUrl,
          progressPercent: watching.progressPercent,
        ),
      );
    }
    for (final movie in recent) {
      if (!seen.add(movie.id)) {
        continue;
      }
      items.add(
        PortalVideoPreviewItem(
          id: movie.id,
          title: movie.title,
          route: '/video/${movie.id}',
          posterUrl: movie.posterImageUrl ?? movie.backdropImageUrl,
          secondaryText: movie.year,
        ),
      );
    }
    return items;
  }
}

final portalVideoPreviewProvider = AsyncNotifierProvider<
  PortalVideoPreviewController,
  PortalPagedListState<PortalVideoPreviewItem>
>(PortalVideoPreviewController.new);
