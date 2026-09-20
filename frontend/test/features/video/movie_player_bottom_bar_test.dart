import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_bottom_bar.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_controls.dart';

void main() {
  testWidgets('compact controls fit a narrow mobile viewport', (tester) async {
    await _pumpBottomBar(
      tester,
      size: const Size(320, 568),
      isMobile: true,
      textScaler: const TextScaler.linear(2),
    );

    expect(find.byKey(const Key('moviePlayerControlsCompact')), findsOneWidget);
    expect(find.byIcon(Icons.language_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('medium controls are selected for a constrained desktop window', (
    tester,
  ) async {
    await _pumpBottomBar(tester, size: const Size(1100, 700), isMobile: false);

    expect(find.byKey(const Key('moviePlayerControlsMedium')), findsOneWidget);
    expect(find.byKey(const Key('moviePlayerControlsExpanded')), findsNothing);
    expect(find.byType(SpeedButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('medium mobile controls keep episode playback controls at left', (
    tester,
  ) async {
    await _pumpBottomBar(tester, size: const Size(900, 500), isMobile: true);

    expect(find.byKey(const Key('moviePlayerControlsMedium')), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded controls are selected for a wide desktop window', (
    tester,
  ) async {
    await _pumpBottomBar(tester, size: const Size(1500, 800), isMobile: false);

    expect(
      find.byKey(const Key('moviePlayerControlsExpanded')),
      findsOneWidget,
    );
    expect(find.byType(Slider), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('left and right control groups occupy opposite edges', (
    tester,
  ) async {
    await _pumpBottomBar(tester, size: const Size(1500, 800), isMobile: false);

    final viewportRect = tester.getRect(
      find.byKey(const Key('moviePlayerControlViewport')),
    );
    final contentPadding = tester.widget<AnimatedPadding>(
      find.byKey(const Key('moviePlayerBottomBarContent')),
    );
    final transportRect = tester.getRect(
      find.byKey(const Key('moviePlayerTransportControls')),
    );
    final rightControlsRect = tester.getRect(
      find.byKey(const Key('moviePlayerRightControls')),
    );
    final previousCenter = tester.getCenter(
      find.byIcon(Icons.skip_previous_rounded),
    );
    final playCenter = tester.getCenter(find.byIcon(Icons.play_arrow_rounded));
    final nextCenter = tester.getCenter(find.byIcon(Icons.skip_next_rounded));
    final languageCenter = tester.getCenter(
      find.byIcon(Icons.language_rounded),
    );
    final subtitleCenter = tester.getCenter(
      find.byIcon(Icons.subtitles_off_rounded),
    );
    final speedCenter = tester.getCenter(find.byType(SpeedButton));
    final settingsCenter = tester.getCenter(
      find.byIcon(Icons.settings_rounded),
    );
    final fullscreenCenter = tester.getCenter(
      find.byIcon(Icons.fullscreen_rounded),
    );

    expect(
      transportRect.left,
      closeTo(
        viewportRect.left + (contentPadding.padding as EdgeInsets).left,
        0.1,
      ),
    );
    expect(previousCenter.dx, lessThan(playCenter.dx));
    expect(nextCenter.dx, greaterThan(playCenter.dx));
    expect(
      rightControlsRect.right,
      closeTo(
        viewportRect.right - (contentPadding.padding as EdgeInsets).right,
        0.1,
      ),
    );
    expect(languageCenter.dx, lessThan(subtitleCenter.dx));
    expect(subtitleCenter.dx, lessThan(speedCenter.dx));
    expect(speedCenter.dx, lessThan(settingsCenter.dx));
    expect(settingsCenter.dx, lessThan(fullscreenCenter.dx));
  });

  testWidgets('compact transport controls use a dedicated left row', (
    tester,
  ) async {
    await _pumpBottomBar(tester, size: const Size(320, 568), isMobile: true);

    final viewportRect = tester.getRect(
      find.byKey(const Key('moviePlayerControlViewport')),
    );
    final contentPadding = tester.widget<AnimatedPadding>(
      find.byKey(const Key('moviePlayerBottomBarContent')),
    );
    final transportRect = tester.getRect(
      find.byKey(const Key('moviePlayerTransportControls')),
    );
    final previousCenter = tester.getCenter(
      find.byIcon(Icons.skip_previous_rounded),
    );
    final playCenter = tester.getCenter(find.byIcon(Icons.play_arrow_rounded));
    final nextCenter = tester.getCenter(find.byIcon(Icons.skip_next_rounded));

    expect(
      transportRect.left,
      closeTo(
        viewportRect.left + (contentPadding.padding as EdgeInsets).left,
        0.1,
      ),
    );
    expect(previousCenter.dx, lessThan(playCenter.dx));
    expect(nextCenter.dx, greaterThan(playCenter.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fullscreen keeps control bar pinned near the screen edge', (
    tester,
  ) async {
    await _pumpBottomBar(
      tester,
      size: const Size(1920, 1080),
      isMobile: false,
      isFullscreen: false,
    );
    final windowedPadding = tester.widget<AnimatedPadding>(
      find.byKey(const Key('moviePlayerBottomBarContent')),
    );
    final windowedViewport = tester.getSize(
      find.byKey(const Key('moviePlayerControlViewport')),
    );

    await _pumpBottomBar(
      tester,
      size: const Size(1920, 1080),
      isMobile: false,
      isFullscreen: true,
    );
    final fullscreenPadding = tester.widget<AnimatedPadding>(
      find.byKey(const Key('moviePlayerBottomBarContent')),
    );
    final fullscreenViewport = tester.getSize(
      find.byKey(const Key('moviePlayerControlViewport')),
    );
    final fullscreenButtonRect = tester.getRect(
      find.byIcon(Icons.fullscreen_exit_rounded),
    );
    final fullscreenTransportRect = tester.getRect(
      find.byKey(const Key('moviePlayerTransportControls')),
    );

    expect(
      (fullscreenPadding.padding as EdgeInsets).bottom,
      // 全屏/无边框态控件应贴底，不再按 4K 高度比例抬升。
      lessThanOrEqualTo((windowedPadding.padding as EdgeInsets).bottom + 4),
    );
    expect(windowedViewport.width, 1920);
    expect(fullscreenViewport.width, 1920);
    expect(1920 - fullscreenButtonRect.right, lessThan(80));
    // 控制条底部应贴近窗口底缘。
    expect(1080 - fullscreenTransportRect.bottom, lessThan(40));
  });

  testWidgets('ultrawide fullscreen controls use the full viewport width', (
    tester,
  ) async {
    await _pumpBottomBar(
      tester,
      size: const Size(3840, 2160),
      isMobile: false,
      isFullscreen: true,
    );

    final viewport = tester.getSize(
      find.byKey(const Key('moviePlayerControlViewport')),
    );
    final fullscreenButtonRect = tester.getRect(
      find.byIcon(Icons.fullscreen_exit_rounded),
    );
    expect(viewport.width, 3840);
    expect(3840 - fullscreenButtonRect.right, lessThan(80));
  });

  testWidgets('desktop window resizing crosses responsive control densities', (
    tester,
  ) async {
    await _pumpBottomBar(tester, size: const Size(1500, 800), isMobile: false);
    expect(
      find.byKey(const Key('moviePlayerControlsExpanded')),
      findsOneWidget,
    );

    await _pumpBottomBar(tester, size: const Size(1100, 700), isMobile: false);
    expect(find.byKey(const Key('moviePlayerControlsMedium')), findsOneWidget);

    await _pumpBottomBar(tester, size: const Size(680, 560), isMobile: false);
    expect(find.byKey(const Key('moviePlayerControlsCompact')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpBottomBar(
  WidgetTester tester, {
  required Size size,
  required bool isMobile,
  bool isFullscreen = false,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final position = ValueNotifier<Duration>(const Duration(seconds: 12));
  addTearDown(position.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: OmniNestTheme.from(AppThemePalette.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(size: size, textScaler: textScaler),
            child: child!,
          ),
      home: Scaffold(
        body: Stack(
          children: [
            MoviePlayerBottomBar(
              plan: const PlaybackPlan(
                videoItemId: 'video-id',
                mode: 'DIRECT_PLAY',
                url: 'https://example.test/video.mp4',
                positionSeconds: 12,
                durationSeconds: 120,
                subtitles: [],
              ),
              polledPosition: position,
              playerDuration: const Duration(seconds: 120),
              bufferProgress: 0.4,
              isSeeking: false,
              seekValue: 0,
              onSeekStart: (_) {},
              onSeeking: (_) {},
              onSeekEnd: (_) {},
              onMouseActivity: () {},
              volume: 80,
              isMuted: false,
              onToggleMute: () {},
              onVolumeChanged: (_) {},
              setPlayerVolume: (_) {},
              playbackSpeed: 1,
              activeSubtitleId: null,
              onAudioTap: () {},
              onSubtitleTap: () {},
              onSpeedTap: () {},
              onSettingsTap: () {},
              onFullscreenTap: () {},
              isFullscreen: isFullscreen,
              formatDuration: (duration) => '00:${duration.inSeconds}',
              playing: Stream<bool>.value(false),
              onPlayPause: () {},
              isMobile: isMobile,
              onPreviousEpisode: () {},
              onNextEpisode: () {},
            ),
          ],
        ),
      ),
    ),
  );

  await tester.pump(const Duration(milliseconds: 240));
}
