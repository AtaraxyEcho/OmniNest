import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/domain/music_models.dart';

/// 播放历史页状态：按日聚合的分组列表与分页游标。
class MusicHistoryState {
  const MusicHistoryState({
    this.groups = const <MusicHistoryDayGroup>[],
    this.totalElements = 0,
    this.loadedCount = 0,
    this.nextPage = 0,
    this.loading = false,
    this.loadingMore = false,
    this.errorMessage,
  });

  final List<MusicHistoryDayGroup> groups;
  final int totalElements;
  final int loadedCount;

  /// 下一次请求的页码（分页计数与条目数解耦）。
  final int nextPage;
  final bool loading;
  final bool loadingMore;
  final String? errorMessage;

  bool get hasMore => loadedCount < totalElements;

  MusicHistoryState copyWith({
    List<MusicHistoryDayGroup>? groups,
    int? totalElements,
    int? loadedCount,
    int? nextPage,
    bool? loading,
    bool? loadingMore,
    String? errorMessage,
    bool clearError = false,
  }) {
    return MusicHistoryState(
      groups: groups ?? this.groups,
      totalElements: totalElements ?? this.totalElements,
      loadedCount: loadedCount ?? this.loadedCount,
      nextPage: nextPage ?? this.nextPage,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// 单日播放历史分组。
class MusicHistoryDayGroup {
  const MusicHistoryDayGroup({
    required this.dayKey,
    required this.label,
    required this.entries,
  });

  final DateTime dayKey;
  final String label;
  final List<MusicPlayHistoryEntry> entries;
}

final musicHistoryControllerProvider =
    AsyncNotifierProvider<MusicHistoryController, MusicHistoryState>(
      MusicHistoryController.new,
    );

/// 分页加载播放历史并按日分组。
class MusicHistoryController extends AsyncNotifier<MusicHistoryState> {
  static const int _pageSize = 50;

  int get _nextPage => state.asData?.value.nextPage ?? 0;

  @override
  Future<MusicHistoryState> build() async {
    try {
      final page = await _api().playHistory(page: 0, size: _pageSize);
      final next = _mergeGroups(const [], page.items);
      return MusicHistoryState(
        groups: next,
        totalElements: page.totalElements,
        loadedCount: page.items.length,
        nextPage: page.page + 1,
      );
    } on Exception catch (error) {
      return const MusicHistoryState().copyWith(
        errorMessage: describeUserFacingError(error).message,
      );
    }
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || !current.hasMore || current.loadingMore) {
      return;
    }
    state = AsyncData(current.copyWith(loadingMore: true));
    final page = _nextPage;
    try {
      final result = await _api().playHistory(page: page, size: _pageSize);
      final latest = state.asData?.value;
      if (latest == null) {
        return;
      }
      final knownKeys = <String>{};
      for (final group in latest.groups) {
        for (final entry in group.entries) {
          knownKeys.add('${entry.playableKey}:${entry.playedAt}');
        }
      }
      final fresh = result.items
          .where(
            (entry) => knownKeys.add('${entry.playableKey}:${entry.playedAt}'),
          )
          .toList(growable: false);
      final merged = _mergeGroups(latest.groups, fresh);
      state = AsyncData(
        latest.copyWith(
          groups: merged,
          totalElements: result.totalElements,
          loadedCount: latest.loadedCount + fresh.length,
          nextPage: result.page + 1,
          loadingMore: false,
        ),
      );
    } on Exception catch (error) {
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

  List<MusicHistoryDayGroup> _mergeGroups(
    List<MusicHistoryDayGroup> existing,
    List<MusicPlayHistoryEntry> additions,
  ) {
    final byDay = <String, List<MusicPlayHistoryEntry>>{};
    final order = <String>[];
    void addEntry(MusicPlayHistoryEntry entry) {
      final local = entry.playedAt.toLocal();
      final key =
          '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
      byDay.putIfAbsent(key, () => []).add(entry);
      if (!order.contains(key)) {
        order.add(key);
      }
    }

    for (final group in existing) {
      for (final entry in group.entries) {
        addEntry(entry);
      }
    }
    for (final entry in additions) {
      addEntry(entry);
    }
    final now = DateTime.now();
    return [
      for (final key in order)
        MusicHistoryDayGroup(
          dayKey: DateTime.parse(key),
          label: _dayLabel(key, now),
          entries:
              byDay[key]!..sort((a, b) => b.playedAt.compareTo(a.playedAt)),
        ),
    ];
  }

  String _dayLabel(String dayKey, DateTime now) {
    return dayKey;
  }

  MusicApi _api() => ref.read(musicApiProvider);
}
