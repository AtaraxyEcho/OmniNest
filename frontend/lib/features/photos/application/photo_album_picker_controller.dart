import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';

/// 相册候选照片选择状态；影集"添加照片"选择页消费。
class PhotoAlbumPickerState {
  const PhotoAlbumPickerState({
    this.albumId,
    this.candidates = const [],
    this.selectedIds = const <String>{},
    this.totalElements = 0,
    this.nextPage = 0,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.isSubmitting = false,
    this.error,
  });

  /// 正在选择照片的相册，进入前为空。
  final String? albumId;
  final List<PhotoItem> candidates;
  final Set<String> selectedIds;
  final int totalElements;

  /// 下一页页码；首页尚未成功返回时为 0，成功后从 1 起递增。
  final int nextPage;
  final bool hasMore;
  final bool isLoadingMore;
  final bool isSubmitting;
  final String? error;

  bool get isInitialLoading =>
      albumId != null && nextPage == 0 && error == null;

  bool get isEmpty => candidates.isEmpty && !isInitialLoading;
}

/// 相册候选照片选择控制器：选择页进入时 open，滚动到底部 loadMore，确认时 submit。
///
/// 使用代计数防止快速切换相册后旧响应覆盖新状态；页面退出不清理，重入由 open 复位。
class PhotoAlbumPickerNotifier extends Notifier<PhotoAlbumPickerState> {
  int _generation = 0;

  @override
  PhotoAlbumPickerState build() => const PhotoAlbumPickerState();

  /// 打开指定相册的选择器：复位选择并拉取候选首页。
  Future<void> open(String albumId) async {
    final generation = ++_generation;
    state = PhotoAlbumPickerState(albumId: albumId);
    try {
      final page = await ref
          .read(photoRepositoryProvider)
          .listAlbumCandidates(albumId: albumId);
      if (generation != _generation) {
        return;
      }
      state = PhotoAlbumPickerState(
        albumId: albumId,
        candidates: page.items,
        totalElements: page.totalElements,
        nextPage: 1,
        hasMore: page.hasMore,
      );
    } on Exception catch (e) {
      if (generation != _generation) {
        return;
      }
      state = PhotoAlbumPickerState(
        albumId: albumId,
        error: describeUserFacingError(e).message,
      );
    }
  }

  /// 加载下一页候选；无更多、正在加载或存在错误时忽略重复触发。
  Future<void> loadMore() async {
    final current = state;
    final albumId = current.albumId;
    if (albumId == null ||
        !current.hasMore ||
        current.isLoadingMore ||
        current.error != null) {
      return;
    }
    final generation = _generation;
    state = PhotoAlbumPickerState(
      albumId: current.albumId,
      candidates: current.candidates,
      selectedIds: current.selectedIds,
      totalElements: current.totalElements,
      nextPage: current.nextPage,
      hasMore: current.hasMore,
      isLoadingMore: true,
    );
    try {
      final page = await ref
          .read(photoRepositoryProvider)
          .listAlbumCandidates(albumId: albumId, page: current.nextPage);
      if (generation != _generation) {
        return;
      }
      final existingIds = current.candidates.map((p) => p.id).toSet();
      final merged = [
        ...current.candidates,
        ...page.items.where((p) => !existingIds.contains(p.id)),
      ];
      state = PhotoAlbumPickerState(
        albumId: current.albumId,
        candidates: merged,
        selectedIds: current.selectedIds,
        totalElements: page.totalElements,
        nextPage: current.nextPage + 1,
        hasMore: page.hasMore,
      );
    } on Exception catch (e) {
      if (generation != _generation) {
        return;
      }
      state = PhotoAlbumPickerState(
        albumId: current.albumId,
        candidates: current.candidates,
        selectedIds: current.selectedIds,
        totalElements: current.totalElements,
        nextPage: current.nextPage,
        hasMore: current.hasMore,
        error: describeUserFacingError(e).message,
      );
    }
  }

  /// 切换一张候选照片的选中状态。
  void toggle(String photoId) {
    final current = state;
    final updated = Set<String>.of(current.selectedIds);
    if (!updated.add(photoId)) {
      updated.remove(photoId);
    }
    state = PhotoAlbumPickerState(
      albumId: current.albumId,
      candidates: current.candidates,
      selectedIds: updated,
      totalElements: current.totalElements,
      nextPage: current.nextPage,
      hasMore: current.hasMore,
      isLoadingMore: current.isLoadingMore,
      isSubmitting: current.isSubmitting,
      error: current.error,
    );
  }

  /// 提交所选照片到相册；提交中或无选择时直接返回结果。
  Future<bool> submit() async {
    final current = state;
    final albumId = current.albumId;
    if (albumId == null ||
        current.selectedIds.isEmpty ||
        current.isSubmitting) {
      return false;
    }
    state = PhotoAlbumPickerState(
      albumId: current.albumId,
      candidates: current.candidates,
      selectedIds: current.selectedIds,
      totalElements: current.totalElements,
      nextPage: current.nextPage,
      hasMore: current.hasMore,
      isSubmitting: true,
    );
    try {
      await ref
          .read(photoRepositoryProvider)
          .addPhotosToAlbum(
            albumId: albumId,
            photoIds: current.selectedIds.toList(),
          );
      ref.invalidate(photoAlbumDetailProvider(albumId));
      final center = ref.read(photoCenterControllerProvider.notifier);
      await center.refresh();
      return true;
    } on Exception catch (e) {
      state = PhotoAlbumPickerState(
        albumId: current.albumId,
        candidates: current.candidates,
        selectedIds: current.selectedIds,
        totalElements: current.totalElements,
        nextPage: current.nextPage,
        hasMore: current.hasMore,
        error: describeUserFacingError(e).message,
      );
      return false;
    }
  }
}

final photoAlbumPickerProvider =
    NotifierProvider<PhotoAlbumPickerNotifier, PhotoAlbumPickerState>(
      PhotoAlbumPickerNotifier.new,
    );
