import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/presentation/widgets/upload_panel.dart';

/// 队列行的操作钮原先固定 34，触屏按边缘外 20px 就点不中；
/// 命中盒抬到 48 后，中心外 20px 仍应触发同一动作。
Future<void> _pumpPanel(
  WidgetTester tester, {
  required Future<void> Function(String taskId) onRemove,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: OmniNestTheme.from(AppThemePalette.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: UploadPanel(
          enabled: true,
          localTasks: const [
            FileUploadClientTask(
              id: 't1',
              fileName: 'clip.mp4',
              sizeBytes: 1000,
              uploadedBytes: 400,
              status: 'UPLOADING',
            ),
          ],
          onPauseLocalTask: (_) {},
          onResumeLocalTask: (_) async {},
          onRemoveLocalTask: onRemove,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('队列操作钮边缘外 20px 仍可命中', (tester) async {
    final removed = <String>[];
    Future<void> remove(String id) async => removed.add(id);
    await _pumpPanel(tester, onRemove: remove);

    final center = tester.getCenter(find.byIcon(Icons.delete_outline_rounded));
    await tester.tapAt(center + const Offset(20, 20));
    await tester.pump();

    expect(removed, ['t1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('中心点击仍命中且不溢出', (tester) async {
    final removed = <String>[];
    Future<void> remove(String id) async => removed.add(id);
    await _pumpPanel(tester, onRemove: remove);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pump();

    expect(removed, ['t1']);
    expect(tester.takeException(), isNull);
  });
}
