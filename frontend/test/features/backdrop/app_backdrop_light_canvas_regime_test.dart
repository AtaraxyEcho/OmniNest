// 环境层两极性分档的真行为守卫：壁纸在两态都保持可见，差别只在被压弱的程度
// 与叠上去的那一层洗色（暗态压暗、浅态洗白）。
// 极性源是外观设置（根主题明暗），壁纸不参与判定。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_scene_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_host.dart';

const String _owner = 'route:/library';

AppBackdropState _wallpaper() {
  final asset = AppBackdropAsset(
    id: 'bundled-wallpaper',
    path: bundledWallpaperAssetPathFor(AppBackdropSelectionTarget.mobile),
    title: 'OmniNest',
    mediaType: AppBackdropMediaType.image,
    sourceType: AppBackdropSourceType.bundled,
    fileSize: 0,
    modifiedAt: DateTime(2026),
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  return AppBackdropState(
    backdrops: <AppBackdropAsset>[asset],
    settings: AppBackdropSettings(
      enabled: true,
      selectedBackdropId: asset.id,
      blurAmount: 0,
    ),
  );
}

class _StubBackdropController extends AppBackdropController {
  _StubBackdropController(this._state);

  final AppBackdropState _state;

  @override
  Future<AppBackdropState> build() async => _state;

  @override
  Future<void> ensureFreshServerUrls({bool force = false}) async {}
}

Future<void> _pumpShellBackdrop(
  WidgetTester tester, {
  required Brightness brightness,
  required AppBackdropPolicy policy,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      appBackdropControllerProvider.overrideWith(
        () => _StubBackdropController(_wallpaper()),
      ),
    ],
  );
  addTearDown(container.dispose);

  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  try {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme:
              brightness == Brightness.light
                  ? OmniNestTheme.light()
                  : OmniNestTheme.dark(),
          home: AppBackdropHost(child: const SizedBox.shrink()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    container
        .read(appBackdropSceneControllerProvider.notifier)
        .request(_owner, policy);
    await tester.pumpAndSettle();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

double _surfaceOpacity(WidgetTester tester) {
  final opacity = tester.widget<AnimatedOpacity>(
    find.descendant(
      of: find.byKey(const ValueKey<String>('omninest.backdrop.surface')),
      matching: find.byType(AnimatedOpacity),
    ),
  );
  return opacity.opacity;
}

Color? _stageFill(WidgetTester tester) {
  final match = find.descendant(
    of: find.byKey(const ValueKey<String>('omninest.backdrop.default')),
    matching: find.byType(ColoredBox),
  );
  if (match.evaluate().isEmpty) {
    return null;
  }
  return tester.widget<ColoredBox>(match.first).color;
}

/// 遮罩层真正画出来的那一层（渐变档是 DecoratedBox，平涂档是 ColoredBox）。
Object? _scrimPaint(WidgetTester tester) {
  final scoped = find.byKey(
    const ValueKey<String>('omninest.backdrop.environment-scrim'),
  );
  for (final type in <Type>[DecoratedBox, ColoredBox]) {
    final match = find.descendant(
      of: scoped,
      matching: find.byWidgetPredicate((widget) => widget.runtimeType == type),
    );
    if (match.evaluate().isNotEmpty) {
      return tester.widget(match.first);
    }
  }
  return null;
}

LinearGradient? _scrimGradient(WidgetTester tester) {
  final paint = _scrimPaint(tester);
  if (paint is! DecoratedBox) {
    return null;
  }
  return (paint.decoration as BoxDecoration).gradient as LinearGradient?;
}

Color? _scrimFlat(WidgetTester tester) {
  final paint = _scrimPaint(tester);
  return paint is ColoredBox ? paint.color : null;
}

void main() {
  testWidgets('浅态工作区三档换成真实画布：照片让位，环境层平涂 #e9eee7', (tester) async {
    for (final policy in <AppBackdropPolicy>[
      AppBackdropPolicy.ambientMedia,
      AppBackdropPolicy.focusReading,
      AppBackdropPolicy.utilitySurface,
    ]) {
      await _pumpShellBackdrop(
        tester,
        brightness: Brightness.light,
        policy: policy,
      );

      // 样例第 4 层：浅态非沉浸档 `.environment > img { opacity: 0 }`，
      // 照片整体退出，不再是"按档降透明度后仍透在上面"。
      expect(
        _surfaceOpacity(tester),
        0,
        reason: '${policy.environmentMode} 浅态照片整体让位给画布',
      );
      expect(
        _scrimFlat(tester),
        const Color(0xFFE9EEE7),
        reason: '${policy.environmentMode} 浅态是平涂画布，不是渐变洗色',
      );
    }
  });

  testWidgets('浅态沉浸档仍是摄影面：满显照片、调色、墨色压暗渐变', (tester) async {
    await _pumpShellBackdrop(
      tester,
      brightness: Brightness.light,
      policy: AppBackdropPolicy.portalMobile,
    );

    expect(_surfaceOpacity(tester), 1);
    // 样例 `[data-mode="immersive"] .environment > img` 的
    // saturate(.82) contrast(1.02) brightness(.84) 合成一层 ColorFiltered。
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('omninest.backdrop.surface')),
        matching: find.byType(ColorFiltered),
      ),
      findsOneWidget,
      reason: '沉浸档浅态必须对照片本身调色',
    );
    final gradient = _scrimGradient(tester);
    expect(gradient, isNotNull);
    expect(gradient!.colors, const <Color>[
      Color(0x1A0B1813),
      Color(0x290A1611),
      Color(0xA308120E),
    ]);
    expect(gradient.stops, <double>[0, 0.42, 1]);
    // 覆盖层是墨色族：给浅色内容一条承载边，而不是把照片洗白。
    expect(gradient.colors.last.r, lessThan(0.1), reason: '收尾是深色不是纸色');
    expect(gradient.colors.first.a, lessThan(0.2), reason: '顶部保持通透，壁纸可见性优先');
  });

  testWidgets('暗极性工作区档位保持壁纸可见与黑色压暗遮罩', (tester) async {
    await _pumpShellBackdrop(
      tester,
      brightness: Brightness.dark,
      policy: AppBackdropPolicy.ambientMedia,
    );

    expect(
      _surfaceOpacity(tester),
      AppEnvironmentPresentation.of(
        AppEnvironmentMode.ambient,
      ).opacityFor(light: false),
    );
    final gradient = _scrimGradient(tester);
    expect(gradient, isNotNull);
    expect(gradient!.colors.first.a, closeTo(0.28, 0.01));
    expect(gradient.colors.last.a, closeTo(0.89, 0.01));
    expect(_stageFill(tester), MobileEnvPalette.dark.stageSolid);
  });

  test('壁纸强度按极性与档位分面：浅态只有沉浸档仍是照片', () {
    const expected = <AppEnvironmentMode, (double, double)>{
      AppEnvironmentMode.immersive: (1, 1),
      AppEnvironmentMode.ambient: (0.48, 0),
      AppEnvironmentMode.focus: (0.28, 0),
      AppEnvironmentMode.utility: (0.14, 0),
    };
    for (final entry in expected.entries) {
      final presentation = AppEnvironmentPresentation.of(entry.key);
      expect(
        presentation.opacityFor(light: false),
        closeTo(entry.value.$1, 0.001),
        reason: '${entry.key} 暗态强度',
      );
      expect(
        presentation.opacityFor(light: true),
        closeTo(entry.value.$2, 0.001),
        reason: '${entry.key} 浅态强度：0 表示换成画布面，照片整体退出',
      );
    }
  });
}
