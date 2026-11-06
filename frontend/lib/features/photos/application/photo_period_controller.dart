import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/session/session_epoch.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/photos/application/photo_repository_providers.dart';
import 'package:omninest/features/photos/domain/photo.dart';

/// 指定年月照片分页状态；由时间线月份进入的期间浏览页消费。
class PhotoPeriodState {
  const PhotoPeriodState({
    this.period,
    this.photos = const [],
    this.totalElements = 0,
    this.nextPage = 0,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.error,
  });

  /// 当前查看的年月，进入前为空。
  final (int, int)? period;

  final List<PhotoItem> photos;
  final int totalElements;

  /// 下一页页码；首页尚未成功返回时为 0，成功后从 1 起递增。
  final int nextPage;
  final bool hasMore;
  final bool isLoadingMore;
  final String? error;

  /// 首页尚未返回（nextPage 仍为 0）且无错误时视为首次加载中。
  bool get isInitialLoading => period != null && nextPage == 0 && error == null;

  bool get isEmpty => photos.isEmpty && !isInitialLoading;
}

/// 指定年月照片分页控制器：期间浏览页进入时调用 open，滚动到底部时调用 loadMore。
///
/// 使用代计数防止快速切换年月后旧响应覆盖新状态；页面退出不清理，重入由 open 复位。
class PhotoPeriodNotifier extends Notifier<PhotoPeriodState> {
  int _generation = 0;

  @override
  PhotoPeriodState build() {
    // 期间浏览持有上一账号的照片与签名地址，换号必须自行清空。
    ref.watch(sessionEpochProvider);
    return const PhotoPeriodState();
  }

  /// 打开指定年月：复位状态并拉取首页。
  Future<void> open(int year, int month) async {
    final generation = ++_generation;
    state = PhotoPeriodState(period: (year, month));
    try {
      final page = await ref
          .read(photoRepositoryProvider)
          .listByPeriod(year: year, month: month);
      if (!ref.mounted || generation != _generation) {
        return;
      }
      state = PhotoPeriodState(
        period: (year, month),
        photos: page.items,
        totalElements: page.totalElements,
        nextPage: 1,
        hasMore: page.hasMore,
      );
    } on Exception catch (e) {
      if (!ref.mounted || generation != _generation) {
        return;
      }
      state = PhotoPeriodState(
        period: (year, month),
        error: describeUserFacingError(e).message,
      );
    }
  }

  /// 加载下一页；无更多或正在加载时忽略重复触发。
  ///
  /// 上一页失败后必须允许直接重试：把 `error != null` 当作入口守卫会让触底加载
  /// 永久锁死，用户只能下拉刷新整页、丢掉滚动位置。
  Future<void> loadMore() async {
    final current = state;
    final period = current.period;
    if (period == null || !current.hasMore || current.isLoadingMore) {
      return;
    }
    final generation = _generation;
    state = PhotoPeriodState(
      period: current.period,
      photos: current.photos,
      totalElements: current.totalElements,
      nextPage: current.nextPage,
      hasMore: current.hasMore,
      isLoadingMore: true,
    );
    try {
      final page = await ref
          .read(photoRepositoryProvider)
          .listByPeriod(
            year: period.$1,
            month: period.$2,
            page: current.nextPage,
          );
      if (!ref.mounted || generation != _generation) {
        return;
      }
      // 回写基准取发布时刻的实况：请求窗口内用户可能已滚动触发下一次加载。
      final live = state;
      final existingIds = live.photos.map((p) => p.id).toSet();
      final merged = [
        ...live.photos,
        ...page.items.where((p) => !existingIds.contains(p.id)),
      ];
      state = PhotoPeriodState(
        period: live.period,
        photos: merged,
        totalElements: page.totalElements,
        nextPage: live.nextPage + 1,
        hasMore: page.hasMore,
      );
    } on Exception catch (e) {
      if (!ref.mounted || generation != _generation) {
        return;
      }
      final live = state;
      state = PhotoPeriodState(
        period: live.period,
        photos: live.photos,
        totalElements: live.totalElements,
        nextPage: live.nextPage,
        hasMore: live.hasMore,
        error: describeUserFacingError(e).message,
      );
    }
  }
}

final photoPeriodProvider =
    NotifierProvider<PhotoPeriodNotifier, PhotoPeriodState>(
      PhotoPeriodNotifier.new,
    );
