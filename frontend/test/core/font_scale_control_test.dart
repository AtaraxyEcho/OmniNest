import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/appearance/application/font_scale_controller.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/widgets/font_scale_control.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _state = FontScalePreset.followSystem;
  });

  Widget host(Widget child) {
    return ProviderScope(
      overrides: [
        fontScaleControllerProvider.overrideWith(() => _FixedController()),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('桌面端点击弹出档位菜单并回写状态', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(host(const FontScaleControl(size: 20)));
      await tester.tap(find.byType(FontScaleControl));
      await tester.pumpAndSettle();

      expect(find.text('字体大小'), findsOneWidget);
      expect(find.text('跟随系统'), findsOneWidget);
      expect(find.text('紧凑'), findsOneWidget);
      expect(find.text('舒适'), findsOneWidget);
      expect(find.text('大'), findsOneWidget);
      expect(find.text('115%'), findsOneWidget);
      expect(find.text('你好，OmniNest'), findsOneWidget);

      await tester.tap(find.text('舒适'));
      await tester.pumpAndSettle();

      expect(_state, FontScalePreset.comfortable);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('移动端点击弹出底部面板并回写状态', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(host(const FontScaleControl(size: 20)));
      await tester.tap(find.byType(FontScaleControl));
      await tester.pumpAndSettle();

      expect(find.text('字体大小'), findsOneWidget);
      expect(find.text('跟随系统'), findsOneWidget);
      expect(find.text('大'), findsOneWidget);

      await tester.tap(find.text('大'));
      await tester.pumpAndSettle();

      expect(_state, FontScalePreset.large);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

FontScalePreset _state = FontScalePreset.followSystem;

class _FixedController extends FontScaleController {
  @override
  FontScalePreset build() => _state;

  @override
  Future<void> setPreset(FontScalePreset preset) async {
    _state = preset;
    state = preset;
  }
}
