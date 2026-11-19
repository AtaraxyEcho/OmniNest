import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/desktop/desktop_router_scope.dart';
import 'package:omninest/app/desktop/pages/desktop_photos_page.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_theme.dart';
import 'package:omninest/features/photos/photo_dashboard.dart';
import 'package:omninest/features/photos/application/photo_display_order_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPhotos(
    WidgetTester tester, {
    bool empty = false,
    List<Override> extra = const <Override>[],
  }) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [...desktopSeedOverrides(empty: empty), ...extra],
        child: wrapDesktop(const DesktopPhotosPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump(const Duration(milliseconds: 320));
  }

  testWidgets('图库按日分组并铺成等高一排', (tester) async {
    await pumpPhotos(tester);

    expect(find.textContaining('4382 PHOTOS'), findsOneWidget);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Favorites'), findsWidgets);
    expect(find.text('Albums'), findsWidgets);

    // 七张种子照片都没有拍摄时间，落到同一个「未知日期」分组里。
    expect(find.textContaining('7 items'), findsOneWidget);
    expect(find.text('Frame 1'), findsOneWidget);
  });

  testWidgets('悬停日期组显示左侧批量选择并可全选该日', (tester) async {
    await pumpPhotos(tester);
    final selectDay = find.byTooltip('Select this day');
    expect(selectDay, findsOneWidget);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(selectDay)));
    await tester.pump(const Duration(milliseconds: 320));
    final fade = find.ancestor(
      of: selectDay,
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(fade.first).opacity, 1);

    await tester.tap(selectDay);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.byTooltip('Deselect this day'), findsOneWidget);
    expect(find.text('7 selected'), findsAtLeastNWidgets(1));
  });

  testWidgets('Ctrl 点选进入选中态，再点第二张是切换而不是打开', (tester) async {
    await pumpPhotos(tester);

    // Ctrl + 点击第一张：进选中集（不跳大图）。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Frame 1'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('1 selected'), findsOneWidget);

    // 选中态下普通点击也是切换：不然一点就跳走，第二张永远选不中。
    await tester.tap(find.text('Frame 2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('2 selected'), findsOneWidget);

    // 最终 polish.css 用 3px 强调色与 5px 白色的双内环，而非外投影。
    expect(
      find.byKey(const ValueKey('desktop-photo-selected-ring-p-0')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('1 selected'), findsNothing);
    expect(find.text('2 selected'), findsNothing);
  });

  testWidgets('长按已选照片拖到目标位：整组选中项一起换位并在松开后保存', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await pumpPhotos(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Frame 1'));
    await tester.tap(find.text('Frame 2'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    final source = find.byKey(const ValueKey('desktop-photo-p-0'));
    final target = find.byKey(const ValueKey('desktop-photo-p-2'));
    final gesture = await tester.startGesture(
      tester.getCenter(source),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 220));
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_PhotoDragFeedback',
      ),
      findsOneWidget,
    );
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(DesktopPhotosPage)),
    );
    expect(container.read(photoDisplayOrderProvider)['library:unknown'], [
      'p-2',
      'p-0',
      'p-1',
      'p-3',
      'p-4',
      'p-5',
      'p-6',
    ]);
    expect(
      container.read(desktopToastProvider).single.message,
      'Moved 2 photos',
    );
  });

  testWidgets('Escape 取消长按拖动后清理预览，再点击打开所点照片', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/photos',
      routes: [
        GoRoute(
          path: '/photos',
          builder: (context, state) => const DesktopPhotosPage(),
        ),
        GoRoute(
          path: '/photos/:photoId',
          builder:
              (context, state) => Center(
                child: Text('viewer:${state.pathParameters['photoId']}'),
              ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopSeedOverrides(),
        child: MaterialApp.router(
          routerConfig: router,
          theme: DesktopTheme.resolve(isDark: true, accent: DesktopAccent.sage),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          builder:
              (context, child) => DesktopRouterScope(
                router: router,
                child: child ?? const SizedBox.shrink(),
              ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump(const Duration(milliseconds: 320));

    final source = find.byKey(const ValueKey<String>('desktop-photo-p-0'));
    final gesture = await tester.startGesture(
      tester.getCenter(source),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 320));
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_PhotoDragFeedback',
      ),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_PhotoDragFeedback',
      ),
      findsNothing,
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey<String>('desktop-photo-p-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('viewer:p-2'), findsOneWidget);
  });

  testWidgets('长按后原地松手不留预览，再点击打开所点照片', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/photos',
      routes: [
        GoRoute(
          path: '/photos',
          builder: (context, state) => const DesktopPhotosPage(),
        ),
        GoRoute(
          path: '/photos/:photoId',
          builder:
              (context, state) => Center(
                child: Text('viewer:${state.pathParameters['photoId']}'),
              ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopSeedOverrides(),
        child: MaterialApp.router(
          routerConfig: router,
          theme: DesktopTheme.resolve(isDark: true, accent: DesktopAccent.sage),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          builder:
              (context, child) => DesktopRouterScope(
                router: router,
                child: child ?? const SizedBox.shrink(),
              ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump(const Duration(milliseconds: 320));

    final source = find.byKey(const ValueKey<String>('desktop-photo-p-0'));
    final gesture = await tester.startGesture(
      tester.getCenter(source),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 320));
    await gesture.up();
    await tester.pump();
    // 原型在每次已激活的长按拖动结束后都屏蔽 250ms 尾随 click：原地
    // 松手只能收起预览，不能误打开被长按的那张照片。
    expect(find.text('viewer:p-0'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));

    final feedback = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_PhotoDragFeedback',
    );
    expect(feedback, findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('desktop-photo-p-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('viewer:p-2'), findsOneWidget);
    expect(feedback, findsNothing);
  });

  testWidgets('收藏页只列收藏的照片', (tester) async {
    await pumpPhotos(tester);
    await tester.tap(find.text('Favorites').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Golden hour'), findsWidgets);
    expect(find.text('Frame 1'), findsNothing);
  });

  testWidgets('地点按 GPS 聚合，卡片给出地名与张数', (tester) async {
    await pumpPhotos(
      tester,
      extra: [
        photoLocationGroupsProvider.overrideWith(
          (ref) async => [
            PhotoGroup(
              groupKey: 'Kyoto',
              photoCount: 12,
              photos: [seededPhoto],
            ),
          ],
        ),
      ],
    );

    await tester.tap(find.text('Places').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    // 地点列表与下方选中地点的标题各出现一次。
    expect(find.text('Kyoto'), findsWidgets);
    expect(find.text('12 photos'), findsWidgets);
  });

  testWidgets('回收站分区给出保留期说明', (tester) async {
    await pumpPhotos(tester);

    await tester.tap(find.text('Trash').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(
      find.textContaining('kept until you delete them permanently'),
      findsWidgets,
    );
  });

  testWidgets('相册页列出相册名与张数', (tester) async {
    await pumpPhotos(tester);
    await tester.tap(find.text('Albums').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('Golden hour'), findsOneWidget);
    expect(find.text('42 items'), findsOneWidget);
  });

  testWidgets('空库时落到空态', (tester) async {
    await pumpPhotos(tester, empty: true);

    expect(find.text('No photos yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
