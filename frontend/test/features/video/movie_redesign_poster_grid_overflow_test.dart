import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_poster_card.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_status.dart';

void main() {
  const items = [
    MovieRedesignCardData(
      id: 'movie-1',
      title: 'A Long Poster Title For Overflow Check',
      subtitle: 'English Original Title',
      year: '2024',
      rating: 8.1,
      status: MovieRedesignStatus.matched,
    ),
    MovieRedesignCardData(
      id: 'movie-2',
      title: '第二张卡片标题',
      year: '2023',
      status: MovieRedesignStatus.pending,
    ),
  ];

  for (final scale in <double>[1.15, 1.3]) {
    testWidgets('新版海报网格在字体档位 $scale 下不溢出', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: OmniNestTheme.dark(),
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
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: const MovieRedesignPosterGrid(items: items),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('第二张卡片标题'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
