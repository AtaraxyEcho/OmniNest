import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/pages/movie_detail_page.dart';

void main() {
  for (final scale in <double>[1.15, 1.3]) {
    testWidgets('详情页编辑态在字体档位 $scale 下不溢出', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            movieDetailProvider('video-1').overrideWith((ref) async => _item),
            videoFavoriteStatusProvider(
              'video-1',
            ).overrideWith((ref) async => false),
            authSessionProvider.overrideWith(() => _AdminSessionNotifier()),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const MovieDetailPage(videoItemId: 'video-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('EDIT'));
      await tester.pump();

      expect(find.byType(TextField), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}

final MovieVideoItem _item = MovieVideoItem(
  id: 'video-1',
  fileNodeId: 'file-1',
  mediaType: 'MOVIE',
  title: 'A Long Movie Title For Overflow Check',
  releaseDate: DateTime(2024, 3, 8),
  runtimeSeconds: 7200,
  metadataStatus: 'READY',
  nfoStatus: 'READY',
  updatedAt: DateTime(2024, 6, 1),
  metadata: const <String, dynamic>{},
  genres: const ['Sci-Fi', 'Drama', 'Thriller'],
  crewMembers: const [MovieCrewMember(name: 'Nolan', job: 'Director')],
  rating: 8.1,
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
