// 托管 For you 影院 hero 回归：配色走环境墨阶与样例按钮族；取数侧守住
// 两条样例语义——hero 是精选位（不因无续播记录而消失），且元数据必须绑
// hero 项自身，避免出现「A 的标题配 B 的评分」。
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/mobile_env_colors.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/data/movie_api.dart';
import 'package:omninest/features/video/presentation/pages/movie_center_page.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_mobile_chips.dart';

Map<String, Object> _movieJson({
  required String id,
  required String title,
  required String releaseDate,
  required double rating,
  int? resolutionHeight,
}) {
  return <String, Object>{
    'id': id,
    'fileNodeId': '$id-node',
    'mediaType': 'MOVIE',
    'title': title,
    'metadataStatus': 'READY',
    'nfoStatus': 'NONE',
    'updatedAt': '2026-10-01T00:00:00Z',
    'releaseDate': releaseDate,
    'rating': rating,
    'runtimeSeconds': 7200,
    'posterUrl': 'https://cdn.example.test/$id.jpg',
    if (resolutionHeight != null) 'resolutionHeight': resolutionHeight,
  };
}

Map<String, Object> _continueJson({required String id, required String title}) {
  return <String, Object>{
    'id': id,
    'title': title,
    'positionSeconds': 480,
    'durationSeconds': 1200,
    'progressPercent': 40,
    'mediaType': 'MOVIE',
    'updatedAt': '2026-10-01T00:00:00Z',
  };
}

/// 托管 For-you 取数替身：三个列表各自可控，其余端点回空集合。
class _HeroLibraryAdapter implements HttpClientAdapter {
  _HeroLibraryAdapter({
    this.continueWatching = const <Map<String, Object>>[],
    this.recentlyAdded = const <Map<String, Object>>[],
    this.libraryItems = const <Map<String, Object>>[],
  });

  final List<Map<String, Object>> continueWatching;
  final List<Map<String, Object>> recentlyAdded;
  final List<Map<String, Object>> libraryItems;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = switch (options.path) {
      '/video/dashboard' => <String, Object>{
        'stats': <String, Object>{
          'movieCount': libraryItems.length,
          'episodeCount': 0,
          'seriesCount': 0,
          'scrapeFailedCount': 0,
        },
        'recentlyAdded': recentlyAdded,
        'continueWatching': continueWatching,
        'series': <Object>[],
      },
      '/video/library/page' => _page(libraryItems),
      '/video/series/by-type/page' => _page(const <Map<String, Object>>[]),
      // 最近添加与续播另有独立端点，返回体是裸列表。
      '/video/recent' => recentlyAdded,
      '/video/continue' => continueWatching,
      _ => <Object>[],
    };
    return ResponseBody.fromString(
      jsonEncode({'code': 200, 'message': 'success', 'data': data}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  static Map<String, Object> _page(List<Map<String, Object>> items) {
    return <String, Object>{
      'items': items,
      'page': 0,
      'size': 36,
      'totalElements': items.length,
      'totalPages': 1,
    };
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _pumpHostedForYou(
  WidgetTester tester,
  _HeroLibraryAdapter adapter,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
        movieApiProvider.overrideWithValue(
          MovieApi(
            ApiClient(
              const AppEnvironment(
                apiBaseUrl: 'http://localhost:8080/api/v1',
                wsBaseUrl: 'ws://localhost:8080/ws',
              ),
              httpClientAdapter: adapter,
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: OmniNestTheme.from(AppThemePalette.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        // 托管标记由壳层提供，与 MobileHostedRoute 同形态。
        home: MobileShellScope(
          hosted: true,
          child: Scaffold(
            backgroundColor: const Color(0xFF0B1110),
            body: MovieCenterPage(
              initialSection: MovieSection.continueWatching,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _heroText(String text) {
  return find.descendant(
    of: find.byType(MovieMobileCinemaHero),
    matching: find.text(text),
  );
}

Future<void> _pumpHero(
  WidgetTester tester, {
  required String eyebrow,
  required String primaryLabel,
  String? metaLine,
  VoidCallback? onPlay,
  VoidCallback? onInfo,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: OmniNestTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: MobileShellScope(
        hosted: true,
        child: Scaffold(
          backgroundColor: MobileEnvColors.stage,
          body: SingleChildScrollView(
            child: MovieMobileCinemaHero(
              title: 'Mirage',
              eyebrow: eyebrow,
              primaryLabel: primaryLabel,
              metaLine: metaLine,
              badgeText: '4K · HDR',
              onPlay: onPlay ?? () {},
              onInfo: onInfo ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Material _buttonMaterial(WidgetTester tester, String label) {
  final candidates =
      find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .evaluate()
          .map((element) => element.widget as Material)
          .where(
            (material) =>
                material.shape is RoundedRectangleBorder &&
                (material.shape as RoundedRectangleBorder).borderRadius ==
                    const BorderRadius.all(Radius.circular(22)),
          )
          .toList();
  expect(candidates, hasLength(1), reason: '$label 只应有一个 hero 按钮容器');
  return candidates.single;
}

void main() {
  group('托管取数', () {
    testWidgets('续播项存在时元数据绑 hero 项自身，不取列表首项', (tester) async {
      await _pumpHostedForYou(
        tester,
        _HeroLibraryAdapter(
          // 列表首项是 Alpha，hero 是续播的 Beta：评分必须来自 Beta。
          continueWatching: <Map<String, Object>>[
            _continueJson(id: 'v-2', title: 'Beta'),
          ],
          recentlyAdded: <Map<String, Object>>[
            _movieJson(
              id: 'v-2',
              title: 'Beta',
              releaseDate: '2019-05-06',
              rating: 9.9,
              resolutionHeight: 2160,
            ),
          ],
          libraryItems: <Map<String, Object>>[
            _movieJson(
              id: 'v-1',
              title: 'Alpha',
              releaseDate: '2001-03-04',
              rating: 5.0,
              resolutionHeight: 1080,
            ),
            _movieJson(
              id: 'v-2',
              title: 'Beta',
              releaseDate: '2019-05-06',
              rating: 9.9,
              resolutionHeight: 2160,
            ),
          ],
        ),
      );

      expect(find.byType(MovieMobileCinemaHero), findsOneWidget);
      expect(_heroText('Beta'), findsOneWidget);
      expect(_heroText('2019 · 120 min · ★ 9.9'), findsOneWidget);
      expect(_heroText('4K'), findsOneWidget);
      expect(_heroText('2001 · 120 min · ★ 5.0'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('无续播记录时 hero 退到最近添加首项并显精选文案', (tester) async {
      await _pumpHostedForYou(
        tester,
        _HeroLibraryAdapter(
          recentlyAdded: <Map<String, Object>>[
            _movieJson(
              id: 'v-3',
              title: 'Chasm',
              releaseDate: '2020-07-08',
              rating: 7.2,
              resolutionHeight: 2160,
            ),
          ],
        ),
      );

      expect(find.byType(MovieMobileCinemaHero), findsOneWidget);
      expect(_heroText('Chasm'), findsOneWidget);
      expect(_heroText('精选 · 电影'), findsOneWidget);
      expect(_heroText('立即播放'), findsOneWidget);
      expect(_heroText('2020 · 120 min · ★ 7.2'), findsOneWidget);
      // 精选位不编造进度：进度眉标与剩余时长都不应出现。
      expect(find.textContaining('%'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('库内无任何条目时不渲染 hero', (tester) async {
      await _pumpHostedForYou(tester, _HeroLibraryAdapter());

      expect(find.byType(MovieMobileCinemaHero), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('覆盖层形态', () {
    testWidgets('主钮米白实底、次钮深玻璃描边', (tester) async {
      await _pumpHero(
        tester,
        eyebrow: '继续观看 · 40% · 12 分钟后结束',
        primaryLabel: '续播',
      );

      final primary = _buttonMaterial(tester, '续播');
      final secondary = _buttonMaterial(tester, '详情');
      final secondaryShape = secondary.shape as RoundedRectangleBorder;

      expect(primary.color, MobileEnvColors.buttonInk);
      expect(secondary.color, const Color(0x8C121817));
      expect(secondaryShape.side.color, const Color(0x38FFFFFF));
      expect(tester.takeException(), isNull);
    });

    testWidgets('标题用衬线环境墨色，眉标与元数据取入参', (tester) async {
      await _pumpHero(
        tester,
        eyebrow: '继续观看 · 40% · 12 分钟后结束',
        primaryLabel: '续播',
        metaLine: '8.1 · 2024 · 剧情',
      );

      final title = tester.widget<Text>(find.text('Mirage'));
      expect(title.style?.fontFamily, AppTypography.serifFamily);
      expect(title.style?.color, MobileEnvColors.ink);
      expect(find.textContaining('· 40% ·'), findsOneWidget);
      expect(find.text('8.1 · 2024 · 剧情'), findsOneWidget);
      expect(find.text('4K · HDR'), findsOneWidget);
    });

    testWidgets('无进度态眉标与主钮文案由调用方给定', (tester) async {
      await _pumpHero(
        tester,
        eyebrow: '精选 · 电影',
        primaryLabel: '立即播放',
        metaLine: null,
      );

      expect(find.text('精选 · 电影'), findsOneWidget);
      expect(find.text('立即播放'), findsOneWidget);
      expect(find.textContaining('· 40% ·'), findsNothing);
      // 取不到元数据就不渲染该行，不留空占位。
      expect(find.text('8.1 · 2024 · 剧情'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('续播与详情钮分别回调', (tester) async {
      var played = 0;
      var opened = 0;
      await _pumpHero(
        tester,
        eyebrow: '继续观看 · 40% · 12 分钟后结束',
        primaryLabel: '续播',
        metaLine: '8.1 · 2024 · 剧情',
        onPlay: () => played++,
        onInfo: () => opened++,
      );

      await tester.tap(find.text('续播'));
      await tester.tap(find.text('详情'));
      await tester.pump();

      expect(played, 1);
      expect(opened, 1);
    });
  });
}
