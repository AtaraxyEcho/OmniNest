// 托管影视环境档一致性回归：样例把四个媒体空间都放在活体环境底上，
// 影视托管态不得再自注册 work 覆盖路由级 ambient，也不得铺重设计实底；
// 工位（桌面）态仍压住壁纸，规避 Impeller 对角亮缝的既有实证。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_scene_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_scene_scope.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/presentation/widgets/movie_shell.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required bool hosted,
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer.test(
    overrides: [
      authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: OmniNestTheme.from(AppThemePalette.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: AppBackdropSceneScope(
          // 与 router 的 AppRouteSurface.environmental 同注册（/video → ambient）。
          owner: 'route:/video',
          policy: AppBackdropPolicy.ambientMedia,
          pathPrefix: '/video',
          child: Builder(
            builder:
                (context) => MobileShellScope(
                  hosted: hosted,
                  child: Scaffold(
                    body: MovieShell(
                      section: MovieSection.movies,
                      childOwnsScroll: true,
                      child: const SizedBox(height: 240),
                    ),
                  ),
                ),
          ),
        ),
      ),
    ),
  );
  // 场景注册在 post-frame 完成，多泵一帧再判定。
  await tester.pump();
  return container;
}

Scaffold _shellScaffold(WidgetTester tester) {
  return tester.widget<Scaffold>(
    find
        .descendant(
          of: find.byType(MovieShell),
          matching: find.byType(Scaffold),
        )
        .first,
  );
}

void main() {
  testWidgets('托管态沿用路由级 ambient 档且不铺实底', (tester) async {
    final container = await _pump(
      tester,
      hosted: true,
      size: const Size(390, 844),
    );

    final scene = container.read(appBackdropSceneControllerProvider);
    expect(scene.owner, 'route:/video');
    expect(scene.policy.visible, isTrue);
    expect(scene.policy.environmentMode, AppEnvironmentMode.ambient);
    expect(_shellScaffold(tester).backgroundColor, Colors.transparent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('工位态仍自注册 work 压住壁纸', (tester) async {
    final container = await _pump(
      tester,
      hosted: false,
      size: const Size(1280, 800),
    );

    final scene = container.read(appBackdropSceneControllerProvider);
    expect(scene.owner, 'video.movie.shell');
    expect(scene.policy.visible, isFalse);
    expect(_shellScaffold(tester).backgroundColor, isNot(Colors.transparent));
    expect(tester.takeException(), isNull);
  });
}
