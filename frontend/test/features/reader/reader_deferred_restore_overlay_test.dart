import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_deferred_restore_overlay.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 摘要：回归「恢复定位期间闪现章首再跳到阅读位置」。
///
/// 恢复定位必须等内容就绪才能落位（页模式需重算分页），延迟遮罩
/// 在此窗口内若透出内容，用户会先看到章首；延迟窗口必须以不透明
/// 底色遮盖，仅加载指示延后出现。
void main() {
  testWidgets('延迟窗口内以不透明底色遮盖内容，超时后显示恢复指示', (tester) async {
    final settings = ReaderViewSettings();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Stack(
          children: [
            const Text('章首内容'),
            ReaderDeferredRestoreOverlay(settings: settings),
          ],
        ),
      ),
    );

    // 延迟窗口内：底色遮盖已挂载，加载指示尚未出现。
    expect(find.byKey(const Key('readerRestoreCover')), findsOneWidget);
    final cover = tester.widget<ColoredBox>(
      find.byKey(const Key('readerRestoreCover')),
    );
    expect(cover.color, settings.surfaceColor);
    expect(find.text('Restoring reading position…'), findsNothing);
    expect(find.text('正在恢复阅读位置…'), findsNothing);

    // 超时后：切换为带加载指示的遮罩（默认 locale 为英文）。
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.byKey(const Key('readerRestoreCover')), findsNothing);
    expect(find.text('Restoring reading position…'), findsOneWidget);
  });
}
