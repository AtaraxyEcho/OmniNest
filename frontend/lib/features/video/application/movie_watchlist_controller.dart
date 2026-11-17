import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/session/session_epoch.dart';
import 'package:omninest/features/video/application/movie_engagement_actions.dart';
import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _legacyWatchlistKey = 'desktop.movies.watchlist';

/// 用户的影片 Watchlist；变更由视频同步事件传播到其他登录设备。
final movieWatchlistProvider = NotifierProvider.autoDispose<
  MovieWatchlistController,
  List<MovieVideoItem>
>(MovieWatchlistController.new);

class MovieWatchlistController extends Notifier<List<MovieVideoItem>> {
  int _stateRevision = 0;
  bool _actionInFlight = false;
  Future<void> _initialLoad = Future<void>.value();

  @override
  List<MovieVideoItem> build() {
    ref.watch(sessionEpochProvider);
    _initialLoad = _load(++_stateRevision);
    unawaited(_initialLoad);
    return const <MovieVideoItem>[];
  }

  Future<void> _load(int revision) async {
    _actionInFlight = true;
    try {
      var items =
          await ref.read(movieEngagementActionsProvider).watchlistItems();
      if (ref.mounted && revision == _stateRevision) {
        state = items;
      }
      final preferences = await SharedPreferences.getInstance();
      final legacyIds = preferences.getStringList(_legacyWatchlistKey);
      if (legacyIds == null || legacyIds.isEmpty) {
        return;
      }
      final knownIds = items.map((item) => item.id).toSet();
      final actions = ref.read(movieEngagementActionsProvider);
      for (final id in legacyIds.toSet()) {
        if (knownIds.contains(id)) {
          continue;
        }
        await actions.setWatchlist(id, watchlisted: true);
      }
      items = await actions.watchlistItems();
      if (ref.mounted && revision == _stateRevision) {
        state = items;
      }
      await preferences.remove(_legacyWatchlistKey);
    } on Object {
      // 首次加载失败保留当前值，后续用户动作会显示可见的失败反馈。
    } finally {
      _actionInFlight = false;
    }
  }

  bool contains(String id) => state.any((item) => item.id == id);

  /// 目标状态落到服务端后返回 true（加入）或 false（移除）。
  Future<bool?> toggle(MovieVideoItem item) async {
    if (_actionInFlight) {
      await _initialLoad;
    }
    if (!ref.mounted || _actionInFlight) {
      return null;
    }
    _actionInFlight = true;
    final revision = ++_stateRevision;
    final previous = state;
    final added = !contains(item.id);
    state =
        added
            ? [...state, item]
            : state
                .where((entry) => entry.id != item.id)
                .toList(growable: false);
    try {
      await ref
          .read(movieEngagementActionsProvider)
          .setWatchlist(item.id, watchlisted: added);
      if (!ref.mounted) {
        return added;
      }
      final refreshed =
          await ref.read(movieEngagementActionsProvider).watchlistItems();
      if (ref.mounted && revision == _stateRevision) {
        state = refreshed;
      }
      return added;
    } on Object {
      if (ref.mounted && revision == _stateRevision) {
        state = previous;
      }
      rethrow;
    } finally {
      _actionInFlight = false;
    }
  }
}
