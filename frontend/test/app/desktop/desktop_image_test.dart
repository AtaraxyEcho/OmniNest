import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/widgets/desktop_surfaces.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('图片解码前铺一层渐变微光，不是死板灰块', (tester) async {
    final bytes =
        (await rootBundle.load(
          'assets/backdrops/default_wallpaper.jpg',
        )).buffer.asUint8List();

    await HttpOverrides.runZoned(
      () async {
        await tester.pumpWidget(
          wrapDesktop(
            Center(
              child: SizedBox(
                width: 200,
                height: 120,
                child: DesktopImage(url: 'https://example.test/cover.jpg'),
              ),
            ),
          ),
        );
        // 首帧还没解码：占位是带 LinearGradient 的扫光层。
        await tester.pump();
        final shimmer = find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              (widget.decoration as BoxDecoration).gradient is LinearGradient,
        );
        expect(shimmer, findsOneWidget);

        // 测试环境里图片解码不会真的完成（见 memory 里的封面坑位），
        // 这里只校验加载态与「不抛异常」，淡入路径由实现保证。
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.takeException(), isNull);
      },
      createHttpClient:
          (context) => DesktopImageOverrides(bytes).createHttpClient(context),
    );
  });
}
