import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/data/movie_api.dart';

void main() {
  test('分区选择在 controller 重建（实时刷新 invalidate）后保持', () async {
    final container = _container();

    final first = await container.read(movieCenterControllerProvider.future);
    expect(first.section, MovieSection.movies);
    container.listen(movieCenterControllerProvider, (_, _) {});

    container
        .read(movieCenterControllerProvider.notifier)
        .selectSection(MovieSection.management);
    expect(
      container.read(movieCenterControllerProvider).requireValue.section,
      MovieSection.management,
    );

    container.invalidate(movieCenterControllerProvider);
    final rebuilt = await container.read(movieCenterControllerProvider.future);

    expect(rebuilt.section, MovieSection.management);
  });

  test('controller 重建期间写入的分区偏好在 build 完成后恢复', () async {
    final container = _container();
    container.listen(movieCenterControllerProvider, (_, _) {});

    // 模拟重建进行中用户点击管理分区：分区偏好先写入独立 provider，
    // controller 重建完成后据此恢复而不是回到电影页。
    container
        .read(movieCenterSectionProvider.notifier)
        .select(MovieSection.management);
    container.invalidate(movieCenterControllerProvider);
    final rebuilt = await container.read(movieCenterControllerProvider.future);

    expect(rebuilt.section, MovieSection.management);
  });

  test('同一完成态扫描 run 只触发一次中心数据重载', () async {
    final adapter = _MovieApiAdapter();
    final container = _container(adapter: adapter);
    container.listen(movieCenterControllerProvider, (_, _) {});
    await container.read(movieCenterControllerProvider.future);
    final initialBuilds = adapter.dashboardRequests;

    final firstSubscription = container.listen(
      latestMediaScanRunProvider('movie'),
      (_, _) {},
    );
    final run = await container.read(
      latestMediaScanRunProvider('movie').future,
    );
    expect(run?.status, 'COMPLETED');
    await pumpEventQueue();
    await container.read(movieCenterControllerProvider.future);

    // 完成态 run 触发一次 invalidate 重载。
    expect(adapter.dashboardRequests, initialBuilds + 1);

    // 模拟面板卸载后重新挂载：轮询流重启，但同一 run 不应再次触发重载。
    firstSubscription.close();
    final secondSubscription = container.listen(
      latestMediaScanRunProvider('movie'),
      (_, _) {},
    );
    await container.read(latestMediaScanRunProvider('movie').future);
    await pumpEventQueue();
    await container.read(movieCenterControllerProvider.future);

    expect(adapter.dashboardRequests, initialBuilds + 1);
    secondSubscription.close();
  });
}

ProviderContainer _container({_MovieApiAdapter? adapter}) {
  final resolvedAdapter = adapter ?? _MovieApiAdapter();
  return ProviderContainer.test(
    overrides: [
      movieApiProvider.overrideWithValue(
        MovieApi(
          ApiClient(
            const AppEnvironment(
              apiBaseUrl: 'http://localhost:8080/api/v1',
              wsBaseUrl: 'ws://localhost:8080/ws',
            ),
            httpClientAdapter: resolvedAdapter,
          ),
        ),
      ),
    ],
  );
}

class _MovieApiAdapter implements HttpClientAdapter {
  int dashboardRequests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = switch (options.path) {
      '/video/dashboard' => _dashboard(),
      '/video/library/page' => _libraryPage(options),
      '/video/tasks' => <Object>[],
      '/video/library-sources/movie/scan-runs/latest' => _completedRun(),
      _ => throw StateError('未处理的测试请求: ${options.path}'),
    };
    return ResponseBody.fromString(
      jsonEncode({'code': 200, 'message': 'success', 'data': data}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  Map<String, Object> _dashboard() {
    dashboardRequests++;
    return {
      'stats': {
        'movieCount': 1,
        'episodeCount': 0,
        'seriesCount': 0,
        'scrapeFailedCount': 0,
      },
      'recentlyAdded': <Object>[],
      'continueWatching': <Object>[],
      'series': <Object>[],
    };
  }

  Map<String, Object> _libraryPage(RequestOptions options) {
    return {
      'items': <Object>[_movie('movie-1')],
      'page': 0,
      'size': 36,
      'totalElements': 1,
      'totalPages': 1,
    };
  }

  Map<String, Object> _movie(String id) {
    return {
      'id': id,
      'fileNodeId': 'file-$id',
      'mediaType': 'MOVIE',
      'title': id,
      'metadataStatus': 'MATCHED',
      'availabilityStatus': 'AVAILABLE',
    };
  }

  Map<String, Object> _completedRun() {
    return {
      'id': 'run-1',
      'librarySourceId': 'movie',
      'generation': 1,
      'selectionRevision': 0,
      'status': 'COMPLETED',
      'phase': 'DONE',
      'discoveredCount': 0,
      'candidateCount': 0,
      'existingCount': 0,
      'conflictCount': 0,
      'unmatchedCount': 0,
      'missingCount': 0,
      'selectedCount': 0,
      'appliedCount': 0,
      'failedCount': 0,
    };
  }

  @override
  void close({bool force = false}) {}
}
