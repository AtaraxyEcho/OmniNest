import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/pages/desktop_splash_page.dart';
import 'package:omninest/core/widgets/brand_logo.dart';

import 'desktop_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('启动页给品牌标与字标', (tester) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrapDesktop(const DesktopSplashPage()));
    await tester.pump();

    expect(find.byType(BrandLogo), findsOneWidget);
    expect(find.text('OmniNest'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
