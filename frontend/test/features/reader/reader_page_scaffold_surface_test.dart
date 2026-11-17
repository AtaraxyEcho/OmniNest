import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_scaffold.dart';

/// 摘要：从别的空间 push 进来的阅读子页必须自铺底。
///
/// 跨分支 push 后壳层仍停在来源分支（实测 `push('/reader/items/1')` 会把来源页
/// 卸载、`currentIndex` 不变），壳层 chrome 与来源空间注册的环境档还在画；页面
/// 透明时那就是它的底——首页点「继续阅读」量到的横向接缝即此。
void main() {
  Future<Color?> backgroundOf(
    WidgetTester tester, {
    required bool hostedSurface,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authSessionProvider.overrideWith(_GuestSession.new)],
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: MobileShellScope(
            hosted: true,
            child: ReaderPageScaffold(
              target: ReaderPageTarget.library,
              hostedSurface: hostedSurface,
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor;
  }

  testWidgets('托管子页自铺底，空间根页仍坐环境', (tester) async {
    final pushed = await backgroundOf(tester, hostedSurface: true);
    expect(pushed, isNotNull);
    expect(
      pushed!.a,
      closeTo(0.94, 0.001),
      reason: '样例 module-overlay 的 0.94 纸面玻璃，足以盖住来源空间',
    );

    final space = await backgroundOf(tester, hostedSurface: false);
    expect(space, Colors.transparent, reason: '空间根页继续坐在环境上');
  });
}

class _GuestSession extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async => const AuthSessionState();
}
