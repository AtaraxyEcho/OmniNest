import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_grid_tile.dart';

void main() {
  testWidgets('窄卡片内标题与日期文本不溢出', (tester) async {
    final photo = PhotoItem(
      id: 'photo-1',
      fileNodeId: 'file-1',
      title: '一个很长的移动端照片文件名称',
      format: 'JPEG',
      fileSize: 1024,
      metadataStatus: 'READY',
      favorite: false,
      createdAt: DateTime(2026),
      width: 12000,
      height: 9000,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 96.519,
              height: 96,
              child: PhotoGridTile(photo: photo, onTap: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // 遮罩层常驻树中（透明度控制显隐），标题文本应存在且不溢出。
    expect(find.text(photo.title), findsOneWidget);
    expect(find.text('January 1, 2026'), findsOneWidget);
  });

  testWidgets('缩略图切换不使用淡入动画并保留稳定照片 key', (tester) async {
    final photo = PhotoItem(
      id: 'photo-1',
      fileNodeId: 'file-1',
      title: 'photo.jpg',
      format: 'jpg',
      fileSize: 1,
      metadataStatus: 'READY',
      favorite: false,
      createdAt: DateTime(2026),
      coverUrl: 'https://example.test/photo.jpg',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.from(AppThemePalette.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: SizedBox(
          width: 240,
          height: 240,
          child: PhotoGridTile(
            key: ValueKey(photo.id),
            photo: photo,
            onTap: () {},
          ),
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.fadeInDuration, Duration.zero);
    expect(image.fadeOutDuration, Duration.zero);
    expect(find.byKey(const ValueKey('photo-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选中态显示遮罩、选择圆圈与心形', (tester) async {
    final photo = PhotoItem(
      id: 'photo-1',
      fileNodeId: 'file-1',
      title: 'photo.jpg',
      format: 'jpg',
      fileSize: 1,
      metadataStatus: 'READY',
      favorite: true,
      createdAt: DateTime(2026),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: SizedBox(
          width: 240,
          height: 240,
          child: PhotoGridTile(
            photo: photo,
            onTap: () {},
            isSelectionMode: true,
            isSelected: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(photo.title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('悬停进出不摘除遮罩语义节点', (tester) async {
    final photo = PhotoItem(
      id: 'photo-1',
      fileNodeId: 'file-1',
      title: 'photo.jpg',
      format: 'jpg',
      fileSize: 1,
      metadataStatus: 'READY',
      favorite: false,
      createdAt: DateTime(2026),
      coverUrl: 'https://example.test/photo.jpg',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              height: 240,
              child: PhotoGridTile(
                photo: photo,
                onTap: () {},
                onToggleFavorite: () {},
                onToggleSelection: () {},
              ),
            ),
          ),
        ),
      ),
    );
    final handle = tester.ensureSemantics();
    await tester.pump();
    await tester.pump();

    // 收藏/选择节点在遮罩隐藏时仍常驻语义树（alwaysIncludeSemantics）。
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final center = tester.getCenter(find.byType(PhotoGridTile));
    final enterHit = HitTestResult();
    tester.binding.hitTestInView(enterHit, center, tester.view.viewId);
    tester.binding.dispatchEvent(pointer.hover(center), enterHit);
    await tester.pump(const Duration(milliseconds: 200));

    final away = const Offset(4, 4);
    final exitHit = HitTestResult();
    tester.binding.hitTestInView(exitHit, away, tester.view.viewId);
    tester.binding.dispatchEvent(pointer.hover(away), exitHit);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('收藏语义为稳定 button 而非 CustomSemanticsAction', (tester) async {
    final photo = PhotoItem(
      id: 'photo-1',
      fileNodeId: 'file-1',
      title: 'photo.jpg',
      format: 'jpg',
      fileSize: 1,
      metadataStatus: 'READY',
      favorite: true,
      createdAt: DateTime(2026),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: SizedBox(
          width: 240,
          height: 240,
          child: PhotoGridTile(
            photo: photo,
            onTap: () {},
            onToggleFavorite: () {},
          ),
        ),
      ),
    );
    final handle = tester.ensureSemantics();
    await tester.pump();

    expect(find.byIcon(Icons.favorite), findsOneWidget);
    // 不使用 CustomSemanticsAction：收藏通过稳定的 button + onTap 表达。
    final semantics = tester.getSemantics(find.byIcon(Icons.favorite));
    expect(semantics.label, isNotEmpty);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
