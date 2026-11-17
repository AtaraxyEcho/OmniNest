import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_center_controls.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_status_overlay.dart';

void main() {
  testWidgets('播放计划不可用时保留返回操作', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MoviePlayerFallbackBackButton(
            tooltip: '返回',
            onPressed: () => pressed = true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    expect(pressed, isTrue);
  });

  testWidgets('中央播放控件使用真实播放状态并响应操作', (tester) async {
    final playing = StreamController<bool>();
    addTearDown(playing.close);
    var toggled = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.from(AppThemePalette.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Stack(
          children: [
            MoviePlayerCenterControls(
              playing: playing.stream,
              isMobile: false,
              onPlayPause: () => toggled = true,
              onSeekBackward: () {},
              onSeekForward: () {},
            ),
          ],
        ),
      ),
    );

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    expect(toggled, isTrue);

    playing.add(true);
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
  });

  testWidgets('缓冲覆盖层显示进度指示器', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: MoviePlayerBufferingIndicator()),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
