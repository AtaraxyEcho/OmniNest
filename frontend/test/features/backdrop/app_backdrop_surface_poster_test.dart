import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_surface.dart';

void main() {
  testWidgets('视频背景打开失败或未就绪时保留内置海报兜底', (tester) async {
    final asset = AppBackdropAsset(
      id: bundledDefaultWallpaperId,
      path: 'C:/omninest-test/default_wallpaper_v1.mp4',
      title: 'OmniNest',
      mediaType: AppBackdropMediaType.video,
      sourceType: AppBackdropSourceType.bundled,
      fileSize: 1,
      modifiedAt: DateTime(2026),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AppBackdropSurface(
              asset: asset,
              settings: const AppBackdropSettings(),
              policy: AppBackdropPolicy.portalMobile,
              active: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    bool isPosterImage(Widget widget) =>
        widget is Image && widget.image is AssetImage;

    // 视频会话尚未就绪时,内置海报必须已经渲染,背景层不得整层空白。
    expect(find.byWidgetPredicate(isPosterImage), findsOneWidget);

    // 推进打开超时与重试窗口后,海报仍然存在。
    await tester.pump(const Duration(seconds: 40));
    expect(find.byWidgetPredicate(isPosterImage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
