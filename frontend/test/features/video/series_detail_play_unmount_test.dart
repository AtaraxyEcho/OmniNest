import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/domain/series_play_target.dart';
import 'package:omninest/features/video/presentation/pages/series_detail_page.dart';

/// 续播解析要跨两次 await：意图回来后如果页面已经退出，
/// 分集 Provider 就必须在 `ref.read` 之前被跳过，否则在已卸载的 WidgetRef 上取值。
void main() {
  testWidgets('续播意图回来时页面已退出则不再读取分集', (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final intentCompleter = Completer<SeriesPlayIntent>();
    var episodeReads = 0;
    final container = ProviderContainer(
      overrides: [
        movieSeriesDetailProvider(
          'series-1',
        ).overrideWith((ref) async => _detail),
        seriesFavoriteProvider('series-1').overrideWith((ref) async => false),
        seriesPlayIntentProvider(
          'series-1',
        ).overrideWith((ref) => intentCompleter.future),
        movieSeriesEpisodesProvider('series-1').overrideWith((ref) async {
          episodeReads++;
          return const <MovieVideoItem>[];
        }),
        authSessionProvider.overrideWith(() => _AdminSessionNotifier()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const SeriesDetailPage(seriesId: 'series-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('播放'));
    await tester.pump();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    );
    intentCompleter.complete(
      const SeriesPlayIntent(kind: SeriesPlayIntentKind.first),
    );
    await tester.pump();

    expect(episodeReads, 0);
    expect(tester.takeException(), isNull);
  });
}

final MovieSeries _series = MovieSeries(
  id: 'series-1',
  title: 'Old Title',
  metadataStatus: 'MATCHED',
  overview: '旧的简介',
  metadata: const <String, dynamic>{},
);

final MovieSeriesDetail _detail = MovieSeriesDetail(
  series: _series,
  seasons: const [],
  cast: const [],
  crew: const [],
);

class _AdminSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async => AuthSessionState(
    user: UserProfile(
      id: 'user-1',
      username: 'admin',
      role: 'ADMIN',
      permissions: const <String>{'media:write'},
    ),
  );
}
