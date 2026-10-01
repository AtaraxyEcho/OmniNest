import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';
import 'package:omninest/features/photos/presentation/pages/photos_page.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_palette.dart';

class _MockPhotoRepository extends Mock implements PhotoRepository {}

class _FakePhotoCenterController extends PhotoCenterController {
  @override
  Future<PhotoCenterState> build() async {
    return PhotoCenterState.empty();
  }
}

Future<Widget> _framePage() async {
  final repository = _MockPhotoRepository();
  when(
    () => repository.dashboard(),
  ).thenAnswer((_) async => PhotoDashboard.empty());
  when(
    () => repository.listAlbumsPage(
      page: any(named: 'page'),
      size: any(named: 'size'),
    ),
  ).thenAnswer((_) async => PhotoAlbumPage.empty());
  when(
    () => repository.listPhotos(
      query: any(named: 'query'),
      page: any(named: 'page'),
      size: any(named: 'size'),
      sort: any(named: 'sort'),
    ),
  ).thenAnswer((_) async => PhotoPage.empty());
  when(
    () => repository.listFavorites(
      query: any(named: 'query'),
      page: any(named: 'page'),
      size: any(named: 'size'),
      sort: any(named: 'sort'),
    ),
  ).thenAnswer((_) async => PhotoPage.empty());
  when(() => repository.listTrash()).thenAnswer((_) async => PhotoPage.empty());

  final router = GoRouter(
    initialLocation: '/photos',
    routes: [
      GoRoute(path: '/photos', builder: (c, s) => const PhotosPage()),
      GoRoute(path: '/portal', builder: (c, s) => const SizedBox()),
    ],
  );
  return ProviderScope(
    overrides: [
      authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
      photoRepositoryProvider.overrideWithValue(repository),
      photoCenterControllerProvider.overrideWith(
        () => _FakePhotoCenterController(),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: OmniNestTheme.from(AppThemePalette.light),
    ),
  );
}

Color? _navItemBackground(WidgetTester tester, Finder label) {
  final container = tester.widget<AnimatedContainer>(
    find.ancestor(of: label, matching: find.byType(AnimatedContainer)).first,
  );
  return (container.decoration as BoxDecoration?)?.color;
}

Color _navItemTextColor(WidgetTester tester, Finder label) {
  final element = tester.element(label);
  return DefaultTextStyle.of(element).style.color ?? const Color(0x00000000);
}

void main() {
  testWidgets('侧栏悬停进入显示悬停底色与墨色文字，移出后恢复', (tester) async {
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(await _framePage());
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    final timelineLabel = find.text('Timeline').first;

    // 悬停进入的中途帧：RGB 通道保持悬停色不变，仅透明度渐变（无黑色闪烁）
    await gesture.moveTo(tester.getCenter(timelineLabel));
    await tester.pump(const Duration(milliseconds: 75));
    final enterMid = _navItemBackground(tester, timelineLabel)!;
    expect(enterMid.r, greaterThan(0.85));
    expect(enterMid.g, greaterThan(0.85));
    await tester.pumpAndSettle();

    expect(_navItemBackground(tester, timelineLabel), FramePalette.hover);
    expect(_navItemTextColor(tester, timelineLabel), FramePalette.ink);

    // 移出中途帧同样不变黑，结束后完全恢复
    await gesture.moveTo(const Offset(900, 400));
    await tester.pump(const Duration(milliseconds: 75));
    final exitMid = _navItemBackground(tester, timelineLabel)!;
    expect(exitMid.r, greaterThan(0.85));
    expect(exitMid.g, greaterThan(0.85));
    await tester.pumpAndSettle();

    expect(
      _navItemBackground(tester, timelineLabel),
      FramePalette.hover.withValues(alpha: 0),
    );
    expect(_navItemTextColor(tester, timelineLabel), FramePalette.muted);
  });
}
