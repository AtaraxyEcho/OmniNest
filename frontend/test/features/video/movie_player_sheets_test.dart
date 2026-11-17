import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_sheets.dart';

void main() {
  for (final scenario in const [
    (name: '窄屏', size: Size(320, 568)),
    (name: '短横屏', size: Size(640, 360)),
    (name: '宽横屏', size: Size(740, 360)),
  ]) {
    testWidgets('${scenario.name}和大字体下字幕列表保持可滚动且不溢出', (tester) async {
      await tester.binding.setSurfaceSize(scenario.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final subtitles = List<PlaybackSubtitle>.generate(
        30,
        (index) => PlaybackSubtitle(
          id: 'subtitle-$index',
          language: 'zh-Hans-very-long-language-name-$index',
          label: '很长的字幕轨道名称用于验证窄屏和大字体布局 $index',
          kind: index.isEven ? 'EXTERNAL' : 'SUBTITLE',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: OmniNestTheme.from(AppThemePalette.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed:
                          () => showSubtitleSheet(
                            context: context,
                            plan: PlaybackPlan(
                              videoItemId: 'video-1',
                              mode: 'DIRECT_PLAY',
                              url: 'https://example.test/video.mp4',
                              positionSeconds: 0,
                              durationSeconds: 600,
                              subtitles: subtitles,
                            ),
                            activeSubtitleId: null,
                            embeddedSubtitles: const [],
                            importedSubtitle: null,
                            onSelect: (_) {},
                            onSelectEmbedded: (_) {},
                            onImport: () async {},
                            onDisable: () {},
                            onClosed: () {},
                          ),
                      child: const Text('open'),
                    ),
                  ),
                ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (var index = 0; index < 6; index++) {
        await tester.drag(find.byType(ListView), const Offset(0, -800));
        await tester.pump();
      }
      expect(find.textContaining('29'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
