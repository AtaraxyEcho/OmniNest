import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/frame_trash_view.dart';

PhotoItem _photo(String id) {
  return PhotoItem(
    id: id,
    fileNodeId: 'file-$id',
    title: 'Photo $id',
    format: 'JPEG',
    fileSize: 1024,
    metadataStatus: 'READY',
    favorite: false,
    createdAt: DateTime(2026),
  );
}

Future<void> _pumpTrashView(
  WidgetTester tester, {
  required ValueChanged<PhotoItem> onRestore,
  required ValueChanged<PhotoItem> onDeleteForever,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      theme: OmniNestTheme.from(AppThemePalette.dark),
      home: Scaffold(
        body: FrameTrashView(
          photos: [_photo('photo-1')],
          isLoading: false,
          onRestore: onRestore,
          onDeleteForever: onDeleteForever,
          onEmptyTrash: () {},
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('长按回收站图格弹出恢复与永久删除操作面板', (tester) async {
    var restored = false;
    var deleted = false;
    await _pumpTrashView(
      tester,
      onRestore: (_) => restored = true,
      onDeleteForever: (_) => deleted = true,
    );

    await tester.longPress(find.text('Photo photo-1'));
    await tester.pumpAndSettle();

    expect(find.text('恢复'), findsNWidgets(2));
    expect(find.text('永久删除'), findsNWidgets(2));

    await tester.tap(find.text('恢复').last);
    await tester.pumpAndSettle();

    expect(restored, isTrue);
    expect(deleted, isFalse);
  });

  testWidgets('操作面板选择永久删除后回调页面层确认', (tester) async {
    var deleted = false;
    await _pumpTrashView(
      tester,
      onRestore: (_) {},
      onDeleteForever: (_) => deleted = true,
    );

    await tester.longPress(find.text('Photo photo-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('永久删除').last);
    await tester.pumpAndSettle();

    // 二次确认已上移到页面层 confirmAndRunFilePurge，视图内不再弹窗。
    expect(deleted, isTrue);
  });
}
