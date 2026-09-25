import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 详情页动作执行状态（收藏 / 编辑保存 / 字幕上传）。
///
/// 将执行中标志与收藏乐观覆盖从 Widget State 迁入 application，
/// 避免页面退出后异步回调写回已卸载的 State，并提供幂等执行保护。
class MovieDetailActionState {
  const MovieDetailActionState({
    this.saving = false,
    this.uploading = false,
    this.favoritedOverride,
  });

  final bool saving;
  final bool uploading;
  final bool? favoritedOverride;

  MovieDetailActionState copyWith({
    bool? saving,
    bool? uploading,
    bool? favoritedOverride,
    bool clearFavoritedOverride = false,
  }) {
    return MovieDetailActionState(
      saving: saving ?? this.saving,
      uploading: uploading ?? this.uploading,
      favoritedOverride:
          clearFavoritedOverride
              ? null
              : (favoritedOverride ?? this.favoritedOverride),
    );
  }
}

class MovieDetailActionController extends Notifier<MovieDetailActionState> {
  bool _saveInFlight = false;
  bool _uploadInFlight = false;
  bool _favoriteInFlight = false;

  @override
  MovieDetailActionState build() {
    return const MovieDetailActionState();
  }

  /// 收藏切换（幂等：执行中重复调用直接返回）。
  ///
  /// [apply] 执行实际写入；失败时回滚乐观覆盖。
  Future<void> toggleFavorite({
    required bool current,
    required Future<void> Function(bool next) apply,
  }) async {
    if (_favoriteInFlight) {
      return;
    }
    _favoriteInFlight = true;
    final next = !current;
    state = state.copyWith(favoritedOverride: next);
    try {
      await apply(next);
      state = state.copyWith(favoritedOverride: next);
    } on Exception {
      state = state.copyWith(favoritedOverride: current);
      rethrow;
    } finally {
      _favoriteInFlight = false;
    }
  }

  /// 清除收藏乐观覆盖（服务端状态已刷新后调用）。
  void clearFavoriteOverride() {
    state = state.copyWith(clearFavoritedOverride: true);
  }

  /// 编辑保存（幂等：执行中重复调用直接返回 false）。
  Future<bool> save(Future<void> Function() apply) async {
    if (_saveInFlight) {
      return false;
    }
    _saveInFlight = true;
    state = state.copyWith(saving: true);
    try {
      await apply();
      return true;
    } finally {
      _saveInFlight = false;
      state = state.copyWith(saving: false);
    }
  }

  /// 上传字幕（幂等：执行中重复调用直接返回）。
  Future<void> upload(Future<void> Function() apply) async {
    if (_uploadInFlight) {
      return;
    }
    _uploadInFlight = true;
    state = state.copyWith(uploading: true);
    try {
      await apply();
    } finally {
      _uploadInFlight = false;
      state = state.copyWith(uploading: false);
    }
  }
}

final movieDetailActionProvider = NotifierProvider.autoDispose<
  MovieDetailActionController,
  MovieDetailActionState
>(MovieDetailActionController.new);
