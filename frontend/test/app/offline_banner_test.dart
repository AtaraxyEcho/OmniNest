import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/widgets/offline_banner.dart';

/// 离线横幅的三条主张：断网要出现、在线不出现、**首帧前也不出现**。
///
/// 第三条是这次修复的动机本身：AGENTS 承诺 Web 断网显示横幅，而连接状态是流，
/// 未收到首个事件时是 null；若把 null 当离线，每次冷启动都会闪一条假提示。
void main() {
  const offlineText = '当前处于离线状态，部分操作暂不可用';

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Stream<bool>? status,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (status != null)
            appOnlineStatusProvider.overrideWith((_) => status),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          theme: OmniNestTheme.from(AppThemePalette.light),
          home: OfflineBannerLayer(child: child),
        ),
      ),
    );
    await tester.pump();
  }

  const canvas = ColoredBox(color: Colors.white);

  testWidgets('断网时显示离线横幅', (tester) async {
    await pump(tester, canvas, status: Stream.value(false));
    expect(find.text(offlineText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('在线时不显示', (tester) async {
    await pump(tester, canvas, status: Stream.value(true));
    expect(find.text(offlineText), findsNothing);
  });

  testWidgets('尚未收到连接事件时不闪提示', (tester) async {
    // 不给任何事件也不覆盖：provider 停在 loading，等价于"还不知道"。
    await pump(tester, canvas, status: StreamController<bool>().stream);
    expect(find.text(offlineText), findsNothing);
  });

  testWidgets('横幅不拦截自身之外的点击，且不随时间消失', (tester) async {
    var tapped = false;
    await pump(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: TextButton(
          onPressed: () => tapped = true,
          child: const Text('below'),
        ),
      ),
      status: Stream.value(false),
    );

    await tester.tap(find.text('below'));
    expect(tapped, isTrue);
    // 常驻状态提示，不是一次性 toast：推进时间后仍在。
    await tester.pump(const Duration(seconds: 8));
    expect(find.text(offlineText), findsOneWidget);
  });
}
